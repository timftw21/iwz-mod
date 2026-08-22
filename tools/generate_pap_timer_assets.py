#!/usr/bin/env python3
"""Generate the IW7 ZoneTool source assets for the stock PaP timer housing.

The housing is zero-based world surface 2335 in cp_zmb (the older diagnostic
handoff labeled it 2334). Its five-sided 32x3x16 brush
was omitted from the other film versions of the shared projection room. The
runtime restores the surface to each film's GfxWorld; this generator packages
the original world material and a block-exact crop of the authored Spaceland
lightmap used by those vertices.
"""

from __future__ import annotations

import argparse
import json
import shutil
import struct
from pathlib import Path


MATERIAL_NAME = "w/iwz_pap_timer_housing"
MATERIAL_TECHSET = "w_l_sm_replace_i0c0s0n0p0"
SOURCE_WORLD_MATERIAL = "rubber_trim_black"
SOURCE_IMAGES = (
    "rubber_trim_black_n_da2a7072_packed_ng",
    "rubber_trim_black_c_rubber_trim_black_sg_packed_cs",
)
LIGHTMAP_NAME = "iwz_pap_timer"
LIGHTMAP_IMAGES = (
    ("primary", "*lightmap0_primary", 2496, 1376, 256, 128),
    ("secondary", "*lightmap0_secondary", 2496, 2752, 256, 256),
    ("secondunorm", "*lightmap0_secondunorm", 2496, 1376, 256, 128),
)
DEFAULT_STOCK_DUMP = Path(
    "D:/Steam/steamapps/common/Call of Duty - Infinite Warfare/dump"
)
DUMP_STRING = 6
DUMP_ARRAY = 8


def dump_array(data: bytes | None, count: int = 1) -> bytes:
    if data is None or count == 0:
        return struct.pack("<BB", DUMP_ARRAY, 0)
    return struct.pack("<BBI", DUMP_ARRAY, 1, count) + data


def dump_string(value: str | None, kind: int = DUMP_STRING) -> bytes:
    if value is None:
        return struct.pack("<BB", kind, 0)
    return struct.pack("<BB", kind, 1) + value.encode("ascii") + b"\0"


def make_material(output: Path, stock_dump: Path) -> None:
    """Build the housing's original world-lit material under a unique name."""

    assets_dump = stock_dump / "assets"
    source_material = (
        assets_dump / "materials" / "w" / f"{SOURCE_WORLD_MATERIAL}.json"
    )
    source_images = stock_dump / "cp_zmb" / "images"

    if not source_material.is_file():
        raise FileNotFoundError(f"missing dumped source material: {source_material}")

    material = json.loads(source_material.read_text(encoding="utf-8"))
    if material.get("techniqueSet->name") != MATERIAL_TECHSET:
        raise ValueError(
            "unexpected source material technique: "
            f"{material.get('techniqueSet->name')}"
        )

    texture_table = material.get("textureTable", [])
    if len(texture_table) != len(SOURCE_IMAGES):
        raise ValueError(
            f"unexpected source material texture count: {len(texture_table)}"
        )
    for texture, image_name in zip(texture_table, SOURCE_IMAGES):
        texture["image"] = image_name

    material_dir = output / "materials" / "w"
    material_dir.mkdir(parents=True, exist_ok=True)
    (material_dir / "iwz_pap_timer_housing.json").write_text(
        json.dumps(material, indent=4) + "\n", encoding="utf-8"
    )

    custom_material = "iwz_pap_timer_housing"
    state_root = assets_dump / "techsets" / "state" / MATERIAL_TECHSET / "w"
    output_state = output / "techsets" / "state" / MATERIAL_TECHSET / "w"
    output_state.mkdir(parents=True, exist_ok=True)
    for suffix in ("statebits", "statebitsmap", "stateinfo"):
        shutil.copyfile(
            state_root / f"{SOURCE_WORLD_MATERIAL}.{suffix}",
            output_state / f"{custom_material}.{suffix}",
        )

    constant_root = (
        assets_dump / "techsets" / "constantbuffer" / MATERIAL_TECHSET / "w"
    )
    output_constant = (
        output / "techsets" / "constantbuffer" / MATERIAL_TECHSET / "w"
    )
    output_constant.mkdir(parents=True, exist_ok=True)
    for suffix in ("cbi", "cbt"):
        shutil.copyfile(
            constant_root / f"{SOURCE_WORLD_MATERIAL}.{suffix}",
            output_constant / f"{custom_material}.{suffix}",
        )

    image_dir = output / "images"
    image_dir.mkdir(parents=True, exist_ok=True)
    for image_name in SOURCE_IMAGES:
        source_image = source_images / f"{image_name}.iw7Image"
        if not source_image.is_file():
            raise FileNotFoundError(f"missing dumped source image: {source_image}")
        shutil.copyfile(source_image, image_dir / source_image.name)


def read_dumped_image(path: Path) -> tuple[bytearray, str, int]:
    """Read only an iw7Image header and return its pixel-data file offset."""

    with path.open("rb") as source:
        marker = source.read(6)
        if marker != struct.pack("<BBI", DUMP_ARRAY, 1, 1):
            raise ValueError(f"unexpected image header marker: {path}")
        image = bytearray(source.read(0x70))
        if len(image) != 0x70:
            raise ValueError(f"short image header: {path}")
        if source.read(2) != struct.pack("<BB", DUMP_STRING, 1):
            raise ValueError(f"missing image name: {path}")
        name_bytes = bytearray()
        while True:
            byte = source.read(1)
            if not byte:
                raise ValueError(f"unterminated image name: {path}")
            if byte == b"\0":
                break
            name_bytes += byte
        pixel_marker = source.read(6)
        if len(pixel_marker) != 6 or pixel_marker[:2] != struct.pack("<BB", DUMP_ARRAY, 1):
            raise ValueError(f"missing image pixels: {path}")
        pixel_count = struct.unpack_from("<I", pixel_marker, 2)[0]
        if pixel_count != struct.unpack_from("<I", image, 40)[0]:
            raise ValueError(f"image pixel count mismatch: {path}")
        return image, name_bytes.decode("ascii"), source.tell()


def crop_image_pixels(
    source_path: Path,
    image: bytearray,
    pixel_offset: int,
    x: int,
    y: int,
    width: int,
    height: int,
) -> bytes:
    """Copy an aligned rectangle without decoding or recompressing its texels."""

    source_width, source_height = struct.unpack_from("<HH", image, 48)
    image_format = struct.unpack_from("<I", image, 24)[0]
    if x < 0 or y < 0 or x + width > source_width or y + height > source_height:
        raise ValueError(f"crop outside {source_path.name}")

    if image_format in (80, 95):  # BC4_UNORM / BC6H_UF16
        if any(value % 4 for value in (x, y, width, height)):
            raise ValueError(f"BC crop is not block aligned: {source_path.name}")
        block_size = 8 if image_format == 80 else 16
        source_pitch = source_width // 4 * block_size
        row_size = width // 4 * block_size
        first_row = y // 4
        row_count = height // 4
        x_offset = x // 4 * block_size
    elif image_format == 49:  # R8G8_UNORM
        source_pitch = source_width * 2
        row_size = width * 2
        first_row = y
        row_count = height
        x_offset = x * 2
    else:
        raise ValueError(f"unsupported lightmap DXGI format {image_format}: {source_path}")

    pixels = bytearray()
    with source_path.open("rb") as source:
        for row in range(row_count):
            source.seek(pixel_offset + (first_row + row) * source_pitch + x_offset)
            data = source.read(row_size)
            if len(data) != row_size:
                raise ValueError(f"short lightmap row: {source_path}")
            pixels += data
    return bytes(pixels)


def write_dumped_image(path: Path, name: str, image: bytearray, pixels: bytes) -> None:
    struct.pack_into("<IIHH", image, 40, len(pixels), len(pixels),
                     struct.unpack_from("<H", image, 48)[0],
                     struct.unpack_from("<H", image, 50)[0])
    path.write_bytes(
        dump_array(bytes(image)) + dump_string(name) + dump_array(pixels, len(pixels))
    )


def make_lightmap(output: Path, stock_dump: Path) -> None:
    source_root = stock_dump / "cp_zmb" / "images"
    output_images = output / "images"
    output_lightmaps = output / "lightmaps"
    output_images.mkdir(parents=True, exist_ok=True)
    output_lightmaps.mkdir(parents=True, exist_ok=True)

    texture_names = []
    for suffix, source_name, x, y, width, height in LIGHTMAP_IMAGES:
        source_path = source_root / f"{source_name.replace('*', '_')}.iw7Image"
        if not source_path.is_file():
            raise FileNotFoundError(f"missing dumped source lightmap: {source_path}")

        image, actual_name, pixel_offset = read_dumped_image(source_path)
        if actual_name != source_name:
            raise ValueError(f"unexpected lightmap name {actual_name}: {source_path}")
        pixels = crop_image_pixels(source_path, image, pixel_offset, x, y, width, height)
        struct.pack_into("<HH", image, 48, width, height)

        texture_name = f"*iwz_pap_timer_{suffix}"
        texture_names.append(texture_name)
        write_dumped_image(
            output_images / f"{texture_name.replace('*', '_')}.iw7Image",
            texture_name,
            image,
            pixels,
        )

    (output_lightmaps / f"{LIGHTMAP_NAME}.json").write_text(
        json.dumps({"textures": texture_names}, indent=4) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="ZoneTool fastfile asset root")
    parser.add_argument(
        "--stock-dump",
        type=Path,
        default=DEFAULT_STOCK_DUMP,
        help="ZoneTool dump root containing cp_zmb and dumped stock assets",
    )
    args = parser.parse_args()

    make_material(args.output, args.stock_dump)
    make_lightmap(args.output, args.stock_dump)

    print(
        f"generated BSP restoration assets: material={MATERIAL_NAME} "
        f"lightmap={LIGHTMAP_NAME}"
    )


if __name__ == "__main__":
    main()
