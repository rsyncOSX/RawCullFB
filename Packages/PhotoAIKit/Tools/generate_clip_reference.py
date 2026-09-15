#!/usr/bin/env python3
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "open_clip_torch==3.2.0",
#     "pillow>=11,<13",
#     "torch==2.10.0",
#     "torchvision==0.25.0",
#     "transformers==4.57.3",
# ]
#
# [tool.uv]
# index-url = "https://pypi.org/simple"
# ///
"""Generate PyTorch CLIP embeddings for Swift/Core AI parity checks."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import open_clip
import torch
import torch.nn.functional as functional
import transformers
from PIL import Image, ImageOps


def normalized(values: torch.Tensor) -> list[list[float]]:
    return functional.normalize(values, p=2, dim=-1).float().tolist()


def openai_embeddings(
    image_paths: list[Path],
    prompts: list[str],
) -> tuple[list[list[float]], list[list[float]]]:
    source = "openai/clip-vit-base-patch32"
    model = transformers.CLIPModel.from_pretrained(source).eval()
    processor = transformers.CLIPProcessor.from_pretrained(source)
    images = [
        ImageOps.exif_transpose(Image.open(path)).convert("RGB")
        for path in image_paths
    ]
    image_inputs = processor(
        images=images,
        return_tensors="pt",
    )["pixel_values"]
    text_inputs = processor(
        text=prompts,
        return_tensors="pt",
        padding="max_length",
        truncation=True,
        max_length=77,
    )
    with torch.no_grad():
        vision_outputs = model.vision_model(pixel_values=image_inputs)
        image_values = model.visual_projection(vision_outputs[1])
        text_outputs = model.text_model(
            input_ids=text_inputs["input_ids"],
            attention_mask=text_inputs["attention_mask"],
        )
        text_values = model.text_projection(text_outputs[1])
    return normalized(image_values), normalized(text_values)


def openclip_embeddings(
    architecture: str,
    pretrained: str,
    image_paths: list[Path],
    prompts: list[str],
) -> tuple[list[list[float]], list[list[float]]]:
    model, _, preprocess = open_clip.create_model_and_transforms(
        architecture,
        pretrained=pretrained,
        device="cpu",
    )
    model.eval()
    tokenizer = open_clip.get_tokenizer(architecture)
    image_inputs = torch.stack(
        [
            preprocess(
                ImageOps.exif_transpose(Image.open(path)).convert("RGB")
            )
            for path in image_paths
        ]
    )
    text_inputs = tokenizer(prompts)
    with torch.no_grad():
        image_values = model.encode_image(image_inputs, normalize=True)
        text_values = model.encode_text(text_inputs, normalize=True)
    return image_values.float().tolist(), text_values.float().tolist()


def siglip2_embeddings(
    source_dir: Path,
    image_paths: list[Path],
    prompts: list[str],
) -> tuple[list[list[float]], list[list[float]], list[list[int]]]:
    model = transformers.AutoModel.from_pretrained(
        source_dir,
        local_files_only=True,
        attn_implementation="eager",
    ).eval()
    processor = transformers.AutoProcessor.from_pretrained(
        source_dir,
        local_files_only=True,
    )
    images = [
        ImageOps.exif_transpose(Image.open(path)).convert("RGB")
        for path in image_paths
    ]
    image_inputs = processor(images=images, return_tensors="pt")["pixel_values"]
    text_inputs = processor(
        text=prompts,
        return_tensors="pt",
        padding="max_length",
        truncation=True,
        max_length=64,
    )
    attention_mask = text_inputs.get("attention_mask")
    if attention_mask is None:
        attention_mask = text_inputs["input_ids"].ne(0).to(torch.int64)
    with torch.no_grad():
        image_values = model.get_image_features(pixel_values=image_inputs)
        text_values = model.get_text_features(
            input_ids=text_inputs["input_ids"],
            attention_mask=attention_mask,
        )
    return (
        normalized(image_values),
        normalized(text_values),
        text_inputs["input_ids"].tolist(),
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate reference embeddings for clipbench parity.",
    )
    parser.add_argument(
        "--model",
        choices=["openai", "openclip-datacomp", "siglip2"],
        default="openclip-datacomp",
    )
    parser.add_argument(
        "--architecture",
        default="ViT-B-32-256",
    )
    parser.add_argument(
        "--pretrained",
        default="datacomp_s34b_b86k",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        help="Pinned local Hugging Face snapshot used with --model siglip2.",
    )
    parser.add_argument(
        "--image",
        action="append",
        type=Path,
        required=True,
        help="Repeat for each parity image.",
    )
    parser.add_argument(
        "--text",
        action="append",
        required=True,
        help="Repeat for each parity prompt.",
    )
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    image_paths = [path.resolve() for path in arguments.image]
    token_ids = None
    if arguments.model == "openai":
        image_values, text_values = openai_embeddings(
            image_paths,
            arguments.text,
        )
        architecture = "ViT-B-32"
        pretrained = None
    elif arguments.model == "openclip-datacomp":
        image_values, text_values = openclip_embeddings(
            arguments.architecture,
            arguments.pretrained,
            image_paths,
            arguments.text,
        )
        architecture = arguments.architecture
        pretrained = arguments.pretrained
    else:
        if arguments.source_dir is None:
            parser.error("--source-dir is required with --model siglip2")
        image_values, text_values, token_ids = siglip2_embeddings(
            arguments.source_dir.resolve(),
            image_paths,
            arguments.text,
        )
        architecture = "SigLIP2-Base-Patch16-256"
        pretrained = "webli-siglip2"

    reference = {
        "schema_version": 1,
        "source": {
            "model": arguments.model,
            "architecture": architecture,
            "pretrained": pretrained,
        },
        "images": [
            {
                "path": os.path.relpath(
                    path,
                    start=arguments.output.resolve().parent,
                ),
                "embedding": embedding,
            }
            for path, embedding in zip(
                image_paths,
                image_values,
                strict=True,
            )
        ],
        "texts": [
            {
                "text": text,
                "embedding": embedding,
                **({"token_ids": tokens} if token_ids is not None else {}),
            }
            for index, (text, embedding) in enumerate(zip(
                arguments.text,
                text_values,
                strict=True,
            ))
            for tokens in ([token_ids[index]] if token_ids is not None else [[]])
        ],
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("w", encoding="utf-8") as stream:
        json.dump(reference, stream, indent=2)
        stream.write("\n")
    print(f"Wrote {arguments.output}.")


if __name__ == "__main__":
    main()
