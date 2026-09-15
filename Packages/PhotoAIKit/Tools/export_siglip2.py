#!/usr/bin/env python3
# Copyright 2026 Apple Inc.
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "coreai-core==1.0.0b2",
#     "coreai-torch==0.4.1",
#     "torch==2.10.0",
#     "torchvision==0.25.0",
#     "transformers==4.57.3",
# ]
#
# [tool.uv]
# index-url       = "https://pypi.org/simple"
# prerelease      = "allow"
# index-strategy  = "unsafe-best-match"
# ///
"""Export fixed-resolution SigLIP 2 as a PhotoAIKit Core AI bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import time
from pathlib import Path

import torch
import torch.nn.functional as functional
import transformers
from coreai.runtime import AIModelAssetMetadata
from coreai_torch import TorchConverter, get_decomp_table

from model_fingerprint import fingerprint_asset

SOURCE_MODEL = "google/siglip2-base-patch16-256"
SOURCE_REVISION = "3f9f96cb90da5dbc758b01813f2f6f1aee24c1ab"
ARCHITECTURE = "SigLIP2-Base-Patch16-256"
RESOLUTION = 256
CONTEXT_LENGTH = 64
EMBEDDING_DIMENSIONS = 768
IMAGE_MEAN = [0.5, 0.5, 0.5]
IMAGE_STANDARD_DEVIATION = [0.5, 0.5, 0.5]
TOKENIZER_FILES = [
    "config.json",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer.model",
    "tokenizer_config.json",
]


class SigLIP2ImageEncoder(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.vision_model = model.vision_model

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        embeddings = self.vision_model(pixel_values=pixel_values)[1]
        return functional.normalize(embeddings, p=2, dim=-1)


class SigLIP2TextEncoder(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.text_model = model.text_model

    def forward(
        self,
        input_ids: torch.Tensor,
        attention_mask: torch.Tensor,
    ) -> torch.Tensor:
        embeddings = self.text_model(
            input_ids=input_ids.to(torch.int64),
            attention_mask=attention_mask,
        )[1]
        return functional.normalize(embeddings, p=2, dim=-1)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def exported_program(
    module: torch.nn.Module,
    inputs: tuple[torch.Tensor, ...],
) -> torch.export.ExportedProgram:
    exported = torch.export.export(module, args=inputs)
    return exported.run_decompositions(get_decomp_table())


def build_coreai_program(
    source_dir: Path,
    dtype: torch.dtype,
):
    torch.backends.mha.set_fastpath_enabled(False)
    # Google's fixed-resolution SigLIP 2 checkpoints intentionally retain the
    # original `siglip` config/model type. AutoModel follows that declaration;
    # forcing Siglip2Model constructs a flexible-resolution patch projection
    # whose weights are incompatible with this checkpoint.
    model = transformers.AutoModel.from_pretrained(
        source_dir,
        local_files_only=True,
        attn_implementation="eager",
    )
    model.eval().to(dtype)

    image_encoder = SigLIP2ImageEncoder(model).eval().to(dtype)
    text_encoder = SigLIP2TextEncoder(model).eval().to(dtype)
    tokenizer = transformers.AutoTokenizer.from_pretrained(
        source_dir,
        local_files_only=True,
    )
    token_inputs = tokenizer(
        ["puffins portrait"],
        return_tensors="pt",
        padding="max_length",
        truncation=True,
        max_length=CONTEXT_LENGTH,
    )

    image_input = torch.randn(1, 3, RESOLUTION, RESOLUTION, dtype=dtype)
    input_ids = token_inputs["input_ids"].to(torch.int32)
    attention_mask = token_inputs.get("attention_mask")
    if attention_mask is None:
        attention_mask = token_inputs["input_ids"].ne(0)
    attention_mask = attention_mask.to(torch.int32)

    with torch.no_grad(), torch.autocast(device_type="cpu", dtype=dtype):
        image_program = exported_program(image_encoder, (image_input,))
        text_program = exported_program(
            text_encoder,
            (input_ids, attention_mask),
        )

    converter = TorchConverter()
    converter.add_exported_program(
        exported_program=image_program,
        input_names=["pixel_values"],
        output_names=["image_embeds"],
        entrypoint_name="image_encoder",
    )
    converter.add_exported_program(
        exported_program=text_program,
        input_names=["input_ids", "attention_mask"],
        output_names=["text_embeds"],
        entrypoint_name="text_encoder",
    )
    return converter.to_coreai()


def asset_metadata() -> AIModelAssetMetadata:
    metadata = AIModelAssetMetadata()
    metadata.author = "Google Research"
    metadata.license = "Apache-2.0"
    metadata.model_description = (
        "SigLIP 2 Base Patch16 fixed-resolution 256 image and text encoders. "
        f"Source: https://huggingface.co/{SOURCE_MODEL}"
    )
    metadata.creation_date = int(time.time())
    return metadata


def copy_tokenizer(source_dir: Path, bundle_dir: Path) -> None:
    tokenizer_dir = bundle_dir / "tokenizer"
    tokenizer_dir.mkdir(parents=True, exist_ok=True)
    for name in TOKENIZER_FILES:
        source = source_dir / name
        if source.exists():
            shutil.copy2(source, tokenizer_dir / name)


def write_metadata(bundle_dir: Path, asset_name: str, dtype: torch.dtype) -> None:
    dtype_name = str(dtype).split(".")[-1]
    metadata = {
        "metadata_version": "0.4",
        "kind": "embedding",
        "family": "siglip2",
        "source_model": SOURCE_MODEL,
        "source_revision": SOURCE_REVISION,
        "architecture": ARCHITECTURE,
        "pretrained": "webli-siglip2",
        "name": f"siglip2-base-patch16-256-{dtype_name}-static",
        "embedding_dimensions": EMBEDDING_DIMENSIONS,
        "preprocessing_version": "siglip2-srgb-stretch-bilinear-256-chw-v1",
        "preprocessing": {
            "version": "siglip2-srgb-stretch-bilinear-256-chw-v1",
            "width": RESOLUTION,
            "height": RESOLUTION,
            "resize": "stretch",
            "crop": "none",
            "interpolation": "bilinear",
            "mean": IMAGE_MEAN,
            "standard_deviation": IMAGE_STANDARD_DEVIATION,
        },
        "tokenizer": {
            "version": f"siglip2-gemma-tokenizer-{SOURCE_REVISION[:12]}-v1",
            "type": "huggingface-tokenizer-json",
            "context_length": CONTEXT_LENGTH,
            "padding_token_id": 0,
        },
        "functions": {
            "image": "image_encoder",
            "text": "text_encoder",
        },
        "normalization_version": "l2-v1",
        "configuration_version": "coreai-siglip2-dual-encoder-v1",
        "inputs": {
            "image_encoder": {
                "pixel_values": [1, 3, RESOLUTION, RESOLUTION],
            },
            "text_encoder": {
                "input_ids": [1, CONTEXT_LENGTH],
                "attention_mask": [1, CONTEXT_LENGTH],
            },
        },
        "outputs": {
            "image_encoder": ["image_embeds"],
            "text_encoder": ["text_embeds"],
        },
        "assets": {"main": asset_name},
        "asset_fingerprints": {
            "main": fingerprint_asset(bundle_dir / asset_name),
        },
    }
    with (bundle_dir / "metadata.json").open("w", encoding="utf-8") as stream:
        json.dump(metadata, stream, indent=2)
        stream.write("\n")


def write_provenance(source_dir: Path, bundle_dir: Path, asset_name: str) -> None:
    files = {}
    for name in ["model.safetensors", *TOKENIZER_FILES]:
        source = source_dir / name
        if source.exists():
            files[name] = {
                "sha256": sha256(source),
                "bytes": source.stat().st_size,
            }
    provenance = {
        "source_model": SOURCE_MODEL,
        "source_revision": SOURCE_REVISION,
        "source_files": files,
        "coreai_asset": asset_name,
        "coreai_asset_fingerprint": fingerprint_asset(bundle_dir / asset_name),
        "exporter": "PhotoAIKit/Tools/export_siglip2.py",
    }
    with (bundle_dir / "PROVENANCE.json").open("w", encoding="utf-8") as stream:
        json.dump(provenance, stream, indent=2)
        stream.write("\n")


def export_bundle(
    source_dir: Path,
    output_dir: Path,
    bundle_name: str,
    dtype: torch.dtype,
    overwrite: bool,
    keep_source: bool,
) -> Path:
    missing = [name for name in TOKENIZER_FILES if not (source_dir / name).exists()]
    if not (source_dir / "model.safetensors").exists():
        missing.append("model.safetensors")
    if missing:
        raise FileNotFoundError(f"Source snapshot is incomplete: {', '.join(missing)}")

    bundle_dir = output_dir.resolve() / bundle_name
    if bundle_dir.exists():
        if not overwrite:
            raise FileExistsError(f"{bundle_dir} already exists. Pass --overwrite.")
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True)

    program = build_coreai_program(source_dir.resolve(), dtype)
    dtype_name = str(dtype).split(".")[-1]
    base_name = f"siglip2-base-patch16-256_{dtype_name}_static"
    if keep_source:
        source_asset = output_dir.resolve() / f"{base_name}_source.aimodel"
        if source_asset.exists():
            shutil.rmtree(source_asset)
        program.save_asset(source_asset, asset_metadata())

    program.optimize()
    asset_name = f"{base_name}.aimodel"
    program.save_asset(bundle_dir / asset_name, asset_metadata())
    copy_tokenizer(source_dir, bundle_dir)
    write_metadata(bundle_dir, asset_name, dtype)
    write_provenance(source_dir, bundle_dir, asset_name)
    return bundle_dir


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--bundle-name", default="SigLIP2-Base-Patch16-256")
    parser.add_argument(
        "--dtype",
        choices=["float16", "float32"],
        default="float16",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--keep-source", action="store_true")
    arguments = parser.parse_args()
    dtype = torch.float16 if arguments.dtype == "float16" else torch.float32
    bundle = export_bundle(
        source_dir=arguments.source_dir,
        output_dir=arguments.output_dir,
        bundle_name=arguments.bundle_name,
        dtype=dtype,
        overwrite=arguments.overwrite,
        keep_source=arguments.keep_source,
    )
    print(f"[INFO] SigLIP 2 Core AI bundle ready at {bundle}.")


if __name__ == "__main__":
    main()
