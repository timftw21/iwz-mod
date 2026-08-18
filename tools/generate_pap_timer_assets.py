#!/usr/bin/env python3
"""Generate the IW7 ZoneTool source assets for the stock PaP timer housing.

The housing is world surface 2334 in cp_zmb.  Its five-sided 32x3x16 brush
was omitted from the other film versions of the shared projection room.  The
values below preserve the surface's original vertex positions, texture UVs,
packed normals, and packed tangents while translating it to a model-local
origin at the brush bounds midpoint.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
from pathlib import Path


MODEL_NAME = "iwz_pap_timer_housing"
SURFACE_NAME = f"{MODEL_NAME}_lod0"
MATERIAL_NAME = "mopw/iwz_pap_timer_housing"
MATERIAL_TECHSET = "mopw_l_sm_replace_i0c0s0n0p0"
SOURCE_MODEL_MATERIAL = "fac_rubber_trim_black"
SOURCE_IMAGES = (
    "rubber_trim_black_n_da2a7072_packed_ng",
    "rubber_trim_black_c_rubber_trim_black_sg_packed_cs",
)
DEFAULT_STOCK_DUMP = Path(
    "D:/Steam/steamapps/common/Call of Duty - Infinite Warfare/dump"
)
MODEL_CENTER = (-10142.0, 929.5, -1544.0)

# xyz, texcoord, packed normal, packed tangent.  Extracted from cp_zmb's
# transient zone at vertices 103152..103171.
WORLD_VERTICES = (
    ((-10158.0, 928.0, -1536.0), (-172.4375, -77.0), 0xFFF80200, 0xE00803FF),
    ((-10126.0, 931.0, -1536.0), (-171.4375, -77.1875), 0xFFF80200, 0xE00803FF),
    ((-10126.0, 928.0, -1536.0), (-171.4375, -77.0), 0xFFF80200, 0xE00803FF),
    ((-10158.0, 931.0, -1536.0), (-172.4375, -77.1875), 0xFFF80200, 0xE00803FF),
    ((-10158.0, 931.0, -1552.0), (174.09375, 78.0), 0xE0080000, 0x200FFE00),
    ((-10158.0, 931.0, -1536.0), (174.09375, 77.0), 0xE0080000, 0x200FFE00),
    ((-10158.0, 928.0, -1536.0), (174.0, 77.0), 0xE0080000, 0x200FFE00),
    ((-10158.0, 928.0, -1552.0), (174.0, 78.0), 0xE0080000, 0x200FFE00),
    ((-10126.0, 928.0, -1536.0), (174.0, 77.0), 0xE00803FF, 0xE00FFE00),
    ((-10126.0, 931.0, -1536.0), (174.09375, 77.0), 0xE00803FF, 0xE00FFE00),
    ((-10126.0, 931.0, -1552.0), (174.09375, 78.0), 0xE00803FF, 0xE00FFE00),
    ((-10126.0, 928.0, -1552.0), (174.0, 78.0), 0xE00803FF, 0xE00FFE00),
    ((-10126.0, 928.0, -1552.0), (-171.4375, -77.0), 0xC0080200, 0x200803FF),
    ((-10126.0, 931.0, -1552.0), (-171.4375, -77.1875), 0xC0080200, 0x200803FF),
    ((-10158.0, 931.0, -1552.0), (-172.4375, -77.1875), 0xC0080200, 0x200803FF),
    ((-10158.0, 928.0, -1552.0), (-172.4375, -77.0), 0xC0080200, 0x200803FF),
    ((-10158.0, 928.0, -1552.0), (-172.4375, 78.0), 0xE0000200, 0xE00803FF),
    ((-10158.0, 928.0, -1536.0), (-172.4375, 77.0), 0xE0000200, 0xE00803FF),
    ((-10126.0, 928.0, -1536.0), (-171.4375, 77.0), 0xE0000200, 0xE00803FF),
    ((-10126.0, 928.0, -1552.0), (-171.4375, 78.0), 0xE0000200, 0xE00803FF),
)

FACES = (
    (0, 1, 2), (0, 3, 1),
    (4, 5, 6), (4, 6, 7),
    (8, 9, 10), (8, 10, 11),
    (12, 13, 14), (12, 14, 15),
    (16, 17, 18), (16, 18, 19),
)

# GfxWorld keeps 32-bit UVs while an XModel uses two half-floats. Remove a
# whole-number repeat per face before packing: this is texture-equivalent for
# the wrapping rubber material and preserves every original fractional value
# exactly instead of rounding the large world UV coordinates.
UV_OFFSETS = (
    (-172.0, -77.0),
    (174.0, 77.0),
    (174.0, 77.0),
    (-172.0, -77.0),
    (-172.0, 77.0),
)

DUMP_STRING = 6
DUMP_ASSET = 7
DUMP_ARRAY = 8
DUMP_RAW = 10


def dump_array(data: bytes | None, count: int = 1) -> bytes:
    if data is None or count == 0:
        return struct.pack("<BB", DUMP_ARRAY, 0)
    return struct.pack("<BBI", DUMP_ARRAY, 1, count) + data


def dump_raw(data: bytes | None) -> bytes:
    if not data:
        return struct.pack("<BB", DUMP_RAW, 0)
    return struct.pack("<BBI", DUMP_RAW, 1, len(data)) + data


def dump_string(value: str | None, kind: int = DUMP_STRING) -> bytes:
    if value is None:
        return struct.pack("<BB", kind, 0)
    return struct.pack("<BB", kind, 1) + value.encode("ascii") + b"\0"


def pack_texcoord(u: float, v: float) -> int:
    return struct.unpack("<I", struct.pack("<ee", u, v))[0]


def make_material(output: Path, stock_dump: Path) -> None:
    """Build a model-lit material with the timer's original world textures.

    The original surface uses ``w/rubber_trim_black``. IW has no matching
    ``mopw/rubber_trim_black`` asset, and ``mopw/fac_rubber_trim_black`` is a
    different (nearly solid-black) material. Reuse the native model technique
    and state data, but bind the exact two images used by the original surface.
    """

    assets_dump = stock_dump / "assets"
    source_material = (
        assets_dump / "materials" / "mopw" / f"{SOURCE_MODEL_MATERIAL}.json"
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

    material_dir = output / "materials" / "mopw"
    material_dir.mkdir(parents=True, exist_ok=True)
    (material_dir / "iwz_pap_timer_housing.json").write_text(
        json.dumps(material, indent=4) + "\n", encoding="utf-8"
    )

    custom_material = "iwz_pap_timer_housing"
    state_root = assets_dump / "techsets" / "state" / MATERIAL_TECHSET / "mopw"
    output_state = output / "techsets" / "state" / MATERIAL_TECHSET / "mopw"
    output_state.mkdir(parents=True, exist_ok=True)
    for suffix in ("statebits", "statebitsmap", "stateinfo"):
        shutil.copyfile(
            state_root / f"{SOURCE_MODEL_MATERIAL}.{suffix}",
            output_state / f"{custom_material}.{suffix}",
        )

    constant_root = (
        assets_dump / "techsets" / "constantbuffer" / MATERIAL_TECHSET / "mopw"
    )
    output_constant = (
        output / "techsets" / "constantbuffer" / MATERIAL_TECHSET / "mopw"
    )
    output_constant.mkdir(parents=True, exist_ok=True)
    for suffix in ("cbi", "cbt"):
        shutil.copyfile(
            constant_root / f"{SOURCE_MODEL_MATERIAL}.{suffix}",
            output_constant / f"{custom_material}.{suffix}",
        )

    image_dir = output / "images"
    image_dir.mkdir(parents=True, exist_ok=True)
    for image_name in SOURCE_IMAGES:
        source_image = source_images / f"{image_name}.iw7Image"
        if not source_image.is_file():
            raise FileNotFoundError(f"missing dumped source image: {source_image}")
        shutil.copyfile(source_image, image_dir / source_image.name)


def make_xsurface() -> bytes:
    model_surfs = bytearray(0x38)
    struct.pack_into("<Q", model_surfs, 0x00, 1)  # name, replaced by parser
    struct.pack_into("<Q", model_surfs, 0x08, 1)  # surfs, replaced by parser
    struct.pack_into("<H", model_surfs, 0x10, 1)
    struct.pack_into("<I", model_surfs, 0x14, 0x80000000)

    surface = bytearray(0x100)
    struct.pack_into("<HHHBB", surface, 0x00, 0x82, len(WORLD_VERTICES), len(FACES), 1, 0)
    struct.pack_into("<Q", surface, 0x20, 1)  # packed vertices
    struct.pack_into("<Q", surface, 0x28, 1)  # triangle indices
    struct.pack_into("<Q", surface, 0x48, 1)  # rigid vertex lists
    struct.pack_into("<I", surface, 0xE0, 0x80000000)

    # Default IW7 self-visibility: {0, 0, 1, 0}.
    self_visibility = 0x01FE0100
    vertices = bytearray()
    for vertex_index, (xyz, uv, normal, tangent) in enumerate(WORLD_VERTICES):
        local = tuple(xyz[i] - MODEL_CENTER[i] for i in range(3))
        uv_offset = UV_OFFSETS[vertex_index // 4]
        model_uv = (uv[0] - uv_offset[0], uv[1] - uv_offset[1])
        vertices += struct.pack(
            "<3fIIIII",
            *local,
            self_visibility,
            0xFFFFFFFF,
            pack_texcoord(*model_uv),
            normal,
            tangent,
        )

    triangles = b"".join(struct.pack("<HHH", *face) for face in FACES)
    rigid_list = struct.pack("<HHHHQ", 0, len(WORLD_VERTICES), 0, len(FACES), 0)

    result = bytearray()
    result += dump_array(bytes(model_surfs))
    result += dump_string(SURFACE_NAME)
    result += dump_array(bytes(surface))
    result += dump_array(bytes(vertices), len(WORLD_VERTICES))
    result += dump_array(triangles, len(FACES))
    result += dump_array(rigid_list)
    result += dump_raw(None)  # blend verts
    result += dump_raw(None)  # lightmap unwrap
    result += dump_raw(None)  # tension data
    result += dump_raw(None)  # tension accumulation table
    return bytes(result)


def make_xmodel() -> bytes:
    model = bytearray(0x2E0)
    model[0x09] = 1  # hasLods
    model[0x0A] = 0  # maxLoadedLod
    model[0x0B] = 1  # numLods
    model[0x0C] = 0xFF  # no collision LOD
    model[0x0D] = 6  # shadow cutoff after all possible LODs
    struct.pack_into("<I", model, 0x10, 0x40)  # rigid model
    model[0x14] = 1  # numBones
    model[0x15] = 1  # numRootBones
    struct.pack_into("<H", model, 0x1A, 1)  # numsurfs
    struct.pack_into("<f", model, 0x1C, 1.0)
    struct.pack_into("<f", model, 0x28, math.sqrt(16.0**2 + 1.5**2 + 8.0**2))
    struct.pack_into("<3f", model, 0x2C, 0.0, 0.0, 0.0)
    struct.pack_into("<3f", model, 0x38, 16.0, 1.5, 8.0)
    struct.pack_into("<f", model, 0x74, 35.7771)  # longest model edge
    struct.pack_into("<I", model, 0x78, 0x80000000)

    # XModelLodInfo[0].  ZoneTool replaces modelSurfs; the runtime derives
    # the direct surface pointer from that asset during load.
    struct.pack_into("<fHHQ", model, 0xE0, 3500.0, 1, 0, 1)
    struct.pack_into("<I", model, 0xF0, 0x80000000)
    struct.pack_into("<Q", model, 0x110, 1)
    for lod in range(1, 6):
        struct.pack_into("<f", model, 0xE0 + lod * 0x40, 1_000_000.0)
    model[0x2A0] = 0xFF  # default impact type

    base_mat = struct.pack("<8f", 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 2.0)
    bone_info = struct.pack("<7f", 0.0, 0.0, 0.0, 16.0, 1.5, 8.0, 16.0**2 + 1.5**2 + 8.0**2)

    result = bytearray()
    result += dump_array(bytes(model))
    result += dump_string(MODEL_NAME)
    result += dump_string("tag_origin")
    result += dump_array(None)  # parent list
    result += dump_array(None)  # tag angles
    result += dump_array(None)  # tag positions
    result += dump_array(b"\0")  # part classification
    result += dump_array(base_mat)
    result += dump_array(None)  # reactive motion parts
    result += dump_array(None)  # reactive motion tweaks
    result += dump_array(None)  # collision surfaces
    result += dump_array(bone_info)
    result += dump_array(struct.pack("<H", 0))  # inverse high-mip radius
    result += dump_array(struct.pack("<Q", 1))  # material handles
    result += dump_string(MATERIAL_NAME, DUMP_ASSET)
    result += dump_string(SURFACE_NAME, DUMP_ASSET)
    for _ in range(5):
        result += dump_string(None, DUMP_ASSET)
    result += dump_string(None, DUMP_ASSET)  # physics asset
    result += dump_string(None, DUMP_ASSET)  # physics FX shape
    result += dump_array(None)  # physics LOD data
    result += dump_string(None, DUMP_ASSET)  # scriptable mover
    result += dump_string(None, DUMP_ASSET)  # procedural bones
    result += dump_array(None)  # unknown03
    result += dump_array(None)  # unknown vec3
    result += dump_array(None)  # unknown04
    return bytes(result)


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

    xmodel_dir = args.output / "xmodel"
    xsurface_dir = args.output / "xsurface"
    xmodel_dir.mkdir(parents=True, exist_ok=True)
    xsurface_dir.mkdir(parents=True, exist_ok=True)

    xmodel = make_xmodel()
    xsurface = make_xsurface()
    (xmodel_dir / f"{MODEL_NAME}.xmb").write_bytes(xmodel)
    (xsurface_dir / f"{SURFACE_NAME}.xsb").write_bytes(xsurface)
    make_material(args.output, args.stock_dump)

    print(
        f"generated {MODEL_NAME}: xmodel={len(xmodel)} bytes "
        f"xsurface={len(xsurface)} bytes material={MATERIAL_NAME}"
    )


if __name__ == "__main__":
    main()
