#!/usr/bin/env python3
# Copyright 2026 Apple Inc.
#
# Adapted from apple/coreai-models models/clip/export.py.
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "coreai-core==1.0.0b2",
#     "coreai-torch==0.4.1",
#     "open_clip_torch==3.2.0",
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
"""Export OpenAI CLIP or OpenCLIP DataComp as a PhotoAIKit Core AI bundle.

The bundle contains two named functions in one ``.aimodel`` asset:
``image_encoder`` and ``text_encoder``. Keeping the encoders separate avoids
supplying dummy inputs at runtime and makes image and text batch sizes
independent.
"""

from __future__ import annotations

import argparse
import json
import shutil
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import open_clip
import torch
import torch.nn.functional as functional
import transformers
from coreai.runtime import AIModelAssetMetadata
from coreai_torch import TorchConverter, get_decomp_table

from model_fingerprint import fingerprint_asset

CLIP_MEAN = [0.48145466, 0.4578275, 0.40821073]
CLIP_STANDARD_DEVIATION = [0.26862954, 0.26130258, 0.27577711]
TOKENIZER_SOURCE = "openai/clip-vit-base-patch32"
TOKENIZER_CONTEXT_LENGTH = 77


@dataclass(frozen=True)
class ExportSpecification:
    family: str
    source_model: str
    architecture: str
    pretrained: str | None
    resolution: int
    embedding_dimensions: int
    author: str
    model_url: str
    license: str = "MIT"

    @property
    def variant_slug(self) -> str:
        if self.family == "openclip":
            return f"{self.architecture}-{self.pretrained}"
        return Path(self.source_model).name


OPENAI_SPECIFICATION = ExportSpecification(
    family="openai",
    source_model="openai/clip-vit-base-patch32",
    architecture="ViT-B-32",
    pretrained=None,
    resolution=224,
    embedding_dimensions=512,
    author="A. Radford et al.",
    model_url="https://huggingface.co/openai/clip-vit-base-patch32",
)

DATACOMP_SPECIFICATION = ExportSpecification(
    family="openclip",
    source_model="mlfoundations/open_clip",
    architecture="ViT-B-32-256",
    pretrained="datacomp_s34b_b86k",
    resolution=256,
    embedding_dimensions=512,
    author="OpenCLIP contributors",
    model_url=(
        "https://github.com/mlfoundations/open_clip/blob/main/docs/"
        "openclip_results.csv"
    ),
)


class OpenAIImageEncoder(torch.nn.Module):
    def __init__(self, model: transformers.CLIPModel):
        super().__init__()
        self.vision_model = model.vision_model
        self.visual_projection = model.visual_projection

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        vision_outputs = self.vision_model(pixel_values=pixel_values)
        embeddings = self.visual_projection(vision_outputs[1])
        return functional.normalize(embeddings, p=2, dim=-1)


class OpenAITextEncoder(torch.nn.Module):
    def __init__(self, model: transformers.CLIPModel):
        super().__init__()
        self.text_model = model.text_model
        self.text_projection = model.text_projection

    def forward(
        self,
        input_ids: torch.Tensor,
        attention_mask: torch.Tensor,
    ) -> torch.Tensor:
        text_outputs = self.text_model(
            input_ids=input_ids,
            attention_mask=attention_mask,
        )
        embeddings = self.text_projection(text_outputs[1])
        return functional.normalize(embeddings, p=2, dim=-1)


class OpenCLIPImageEncoder(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        embeddings = self.model.encode_image(pixel_values, normalize=False)
        return functional.normalize(embeddings, p=2, dim=-1)


class OpenCLIPTextEncoder(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        # PhotoAIKit and Core AI exchange token IDs as Int32. OpenCLIP's
        # embedding layer expects Int64, so make the conversion part of the
        # exported graph.
        embeddings = self.model.encode_text(
            input_ids.to(torch.int64),
            normalize=False,
        )
        return functional.normalize(embeddings, p=2, dim=-1)


def specification_for(arguments: argparse.Namespace) -> ExportSpecification:
    if arguments.model == "openai":
        return OPENAI_SPECIFICATION
    return ExportSpecification(
        **{
            **DATACOMP_SPECIFICATION.__dict__,
            "architecture": arguments.architecture,
            "pretrained": arguments.pretrained,
        }
    )


def source_revision(model: torch.nn.Module) -> str | None:
    configuration = getattr(model, "config", None)
    return getattr(configuration, "_commit_hash", None)


def make_source_encoders(
    specification: ExportSpecification,
    dtype: torch.dtype,
) -> tuple[torch.nn.Module, torch.nn.Module, str | None]:
    if specification.family == "openai":
        model = transformers.CLIPModel.from_pretrained(specification.source_model)
        revision = source_revision(model)
        image_encoder: torch.nn.Module = OpenAIImageEncoder(model)
        text_encoder: torch.nn.Module = OpenAITextEncoder(model)
    else:
        model, _, _ = open_clip.create_model_and_transforms(
            specification.architecture,
            pretrained=specification.pretrained,
            device="cpu",
        )
        revision = None
        image_encoder = OpenCLIPImageEncoder(model)
        text_encoder = OpenCLIPTextEncoder(model)

    image_encoder.eval().to(dtype)
    text_encoder.eval().to(dtype)
    return image_encoder, text_encoder, revision


def hf_token_inputs(prompts: list[str]) -> dict[str, torch.Tensor]:
    tokenizer = transformers.CLIPTokenizerFast.from_pretrained(TOKENIZER_SOURCE)
    return tokenizer(
        prompts,
        return_tensors="pt",
        padding="max_length",
        truncation=True,
        max_length=TOKENIZER_CONTEXT_LENGTH,
    )


def verify_openclip_tokenizer_parity(specification: ExportSpecification) -> None:
    if specification.family != "openclip":
        return
    prompts = [
        "a photo of a dog",
        "misty mountain",
        "red-headed bird in flight",
    ]
    reference = open_clip.get_tokenizer(specification.architecture)(prompts)
    candidate = hf_token_inputs(prompts)["input_ids"]
    for row in candidate:
        terminal_positions = (row == 49407).nonzero(as_tuple=False)
        if len(terminal_positions) > 0:
            terminal = int(terminal_positions[0].item())
            row[terminal + 1 :] = 0
    if not torch.equal(reference.to(torch.int64), candidate.to(torch.int64)):
        raise RuntimeError(
            "OpenCLIP and PhotoAIKit tokenizer IDs differ. Refusing to export "
            "a bundle whose text encoder would produce invalid rankings."
        )
    print("[INFO] OpenCLIP and PhotoAIKit token IDs match.")


def exported_program(
    module: torch.nn.Module,
    inputs: tuple[torch.Tensor, ...],
    dynamic_shapes: tuple[dict[int, Any], ...] | None,
) -> torch.export.ExportedProgram:
    exported = torch.export.export(
        module,
        args=inputs,
        dynamic_shapes=dynamic_shapes,
    )
    return exported.run_decompositions(get_decomp_table())


def export_encoders(
    image_encoder: torch.nn.Module,
    text_encoder: torch.nn.Module,
    specification: ExportSpecification,
    dtype: torch.dtype,
    dynamic: bool,
):
    image_batch = 2 if dynamic else 1
    text_batch = 3 if dynamic else 1
    image_input = torch.randn(
        image_batch,
        3,
        specification.resolution,
        specification.resolution,
    ).to(dtype)
    token_inputs = hf_token_inputs(
        ["a photo of a dog", "misty mountain", "a flying bird"][:text_batch]
    )
    input_ids = token_inputs["input_ids"].to(torch.int32)
    attention_mask = token_inputs["attention_mask"].to(torch.int32)

    image_shapes = None
    text_shapes: tuple[dict[int, Any], ...] | None = None
    if dynamic:
        image_batch_dimension = torch.export.Dim("image_batch", min=1, max=64)
        text_batch_dimension = torch.export.Dim("text_batch", min=1, max=64)
        image_shapes = ({0: image_batch_dimension},)
        text_input_count = 2 if specification.family == "openai" else 1
        text_shapes = tuple({0: text_batch_dimension} for _ in range(text_input_count))

    with torch.no_grad(), torch.autocast(device_type="cpu", dtype=dtype):
        image_program = exported_program(
            image_encoder,
            (image_input,),
            image_shapes,
        )
        if specification.family == "openai":
            text_program = exported_program(
                text_encoder,
                (input_ids, attention_mask),
                text_shapes,
            )
            text_input_names = ["input_ids", "attention_mask"]
        else:
            text_program = exported_program(
                text_encoder,
                (input_ids,),
                text_shapes,
            )
            text_input_names = ["input_ids"]

    converter = TorchConverter()
    converter.add_exported_program(
        exported_program=image_program,
        input_names=["pixel_values"],
        output_names=["image_embeds"],
        entrypoint_name="image_encoder",
    )
    converter.add_exported_program(
        exported_program=text_program,
        input_names=text_input_names,
        output_names=["text_embeds"],
        entrypoint_name="text_encoder",
    )
    return converter.to_coreai()


def variant_name(
    specification: ExportSpecification,
    dtype: torch.dtype,
    dynamic: bool,
) -> str:
    dtype_name = str(dtype).split(".")[-1]
    batch_kind = "dynamic" if dynamic else "static"
    return f"{specification.variant_slug}_{dtype_name}_{batch_kind}"


def build_aimodel_metadata(
    specification: ExportSpecification,
) -> AIModelAssetMetadata:
    metadata = AIModelAssetMetadata()
    metadata.author = specification.author
    metadata.license = specification.license
    metadata.model_description = (
        f"{specification.architecture} CLIP image and text encoders. "
        f"Source: {specification.model_url}"
    )
    metadata.creation_date = int(time.time())
    return metadata


def save_asset(coreai_program, model_path: Path, specification: ExportSpecification) -> None:
    if model_path.exists():
        shutil.rmtree(model_path)
    coreai_program.save_asset(
        model_path,
        build_aimodel_metadata(specification),
    )


def write_tokenizer(destination: Path) -> None:
    print(f"[INFO] Saving tokenizer from {TOKENIZER_SOURCE} to {destination}...")
    tokenizer = transformers.CLIPTokenizerFast.from_pretrained(TOKENIZER_SOURCE)
    tokenizer.save_pretrained(str(destination))


def write_bundle_metadata(
    bundle_dir: Path,
    specification: ExportSpecification,
    revision: str | None,
    variant: str,
    main_asset: str,
    dynamic: bool,
) -> None:
    image_batch: int | str = "1...64" if dynamic else 1
    text_batch: int | str = "1...64" if dynamic else 1
    text_inputs: dict[str, list[int | str]] = {
        "input_ids": [text_batch, TOKENIZER_CONTEXT_LENGTH],
    }
    if specification.family == "openai":
        text_inputs["attention_mask"] = [
            text_batch,
            TOKENIZER_CONTEXT_LENGTH,
        ]
    metadata = {
        "metadata_version": "0.4",
        "kind": "embedding",
        "family": "clip",
        "source_model": specification.source_model,
        "source_revision": revision,
        "architecture": specification.architecture,
        "pretrained": specification.pretrained,
        "name": variant,
        "embedding_dimensions": specification.embedding_dimensions,
        "preprocessing_version": (
            f"clip-srgb-shortest-center-bicubic-"
            f"{specification.resolution}-chw-v3"
        ),
        "preprocessing": {
            "version": (
                f"clip-srgb-shortest-center-bicubic-"
                f"{specification.resolution}-chw-v3"
            ),
            "width": specification.resolution,
            "height": specification.resolution,
            "resize": "shortest-side",
            "crop": "center",
            "interpolation": "bicubic",
            "mean": CLIP_MEAN,
            "standard_deviation": CLIP_STANDARD_DEVIATION,
        },
        "tokenizer": {
            "version": "clip-bpe-tokenizer-v1",
            "type": "clip-bpe",
            "context_length": TOKENIZER_CONTEXT_LENGTH,
            "padding_token_id": (
                0 if specification.family == "openclip" else 49407
            ),
        },
        "functions": {
            "image": "image_encoder",
            "text": "text_encoder",
        },
        "normalization_version": "l2-v1",
        "configuration_version": "coreai-clip-dual-encoder-v2",
        "inputs": {
            "image_encoder": {
                "pixel_values": [
                    image_batch,
                    3,
                    specification.resolution,
                    specification.resolution,
                ]
            },
            "text_encoder": text_inputs,
        },
        "outputs": {
            "image_encoder": ["image_embeds"],
            "text_encoder": ["text_embeds"],
        },
        "assets": {"main": main_asset},
        "asset_fingerprints": {
            "main": fingerprint_asset(bundle_dir / main_asset),
        },
    }
    metadata_path = bundle_dir / "metadata.json"
    with metadata_path.open("w", encoding="utf-8") as stream:
        json.dump(metadata, stream, indent=2)
        stream.write("\n")
    print(f"[INFO] Wrote metadata to {metadata_path}.")


def create_clip(
    output_dir: Path,
    bundle_name: str,
    specification: ExportSpecification,
    dtype: torch.dtype,
    overwrite: bool,
    dynamic: bool,
) -> None:
    verify_openclip_tokenizer_parity(specification)
    print(
        "[INFO] Sourcing "
        f"{specification.architecture}"
        f"{f' ({specification.pretrained})' if specification.pretrained else ''}..."
    )
    image_encoder, text_encoder, revision = make_source_encoders(
        specification,
        dtype,
    )

    print("[INFO] Running torch export and Core AI conversion...")
    coreai_program = export_encoders(
        image_encoder,
        text_encoder,
        specification,
        dtype,
        dynamic,
    )

    variant = variant_name(specification, dtype, dynamic)
    bundle_dir = output_dir.resolve() / bundle_name
    if bundle_dir.exists():
        if not overwrite:
            raise FileExistsError(f"{bundle_dir} already exists. Pass --overwrite.")
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True, exist_ok=True)

    source_model_path = bundle_dir / f"{variant}_source.aimodel"
    print(f"[INFO] Saving AOT source model to {source_model_path}...")
    save_asset(coreai_program, source_model_path, specification)

    print("[INFO] Optimizing runtime model...")
    coreai_program.optimize()
    model_path = bundle_dir / f"{variant}.aimodel"
    save_asset(coreai_program, model_path, specification)

    write_tokenizer(bundle_dir / "tokenizer")
    write_bundle_metadata(
        bundle_dir,
        specification,
        revision,
        variant,
        model_path.name,
        dynamic,
    )
    print(f"[INFO] CLIP bundle ready at {bundle_dir}.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Export OpenAI CLIP or OpenCLIP DataComp as a "
            "PhotoAIKit-compatible Core AI bundle."
        ),
    )
    parser.add_argument(
        "--model",
        choices=["openai", "openclip-datacomp"],
        default="openclip-datacomp",
        help="Source model preset.",
    )
    parser.add_argument(
        "--architecture",
        default=DATACOMP_SPECIFICATION.architecture,
        help="OpenCLIP architecture (used with --model openclip-datacomp).",
    )
    parser.add_argument(
        "--pretrained",
        default=DATACOMP_SPECIFICATION.pretrained,
        help="OpenCLIP pretrained tag (used with --model openclip-datacomp).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory that will contain the CLIP bundle.",
    )
    parser.add_argument("--bundle-name", default="CLIP-DataComp")
    parser.add_argument(
        "--dtype",
        choices=["float16", "bfloat16", "float32"],
        default="float16",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--dynamic",
        action="store_true",
        help="Export batch dimensions from 1 through 64.",
    )
    arguments = parser.parse_args()

    dtype = {
        "float16": torch.float16,
        "bfloat16": torch.bfloat16,
        "float32": torch.float32,
    }[arguments.dtype]
    create_clip(
        output_dir=arguments.output_dir,
        bundle_name=arguments.bundle_name,
        specification=specification_for(arguments),
        dtype=dtype,
        overwrite=arguments.overwrite,
        dynamic=arguments.dynamic,
    )


if __name__ == "__main__":
    main()
