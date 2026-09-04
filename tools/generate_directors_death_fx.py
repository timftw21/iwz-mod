#!/usr/bin/env python3
"""Clone Rave's soul-jar particles in red for Death Wish.

Layout/serialization: x64-zt iw7/structs.hpp, assets/particle_system.cpp and
utils/io/assetmanager.hpp. Only the 39 KB jar asset is read. References are
expanded into independent records so recoloring cannot alter shared alpha,
size or intensity curves. The four materials resolve from the loaded Rave map.
"""

import argparse
from pathlib import Path
import struct

SOURCE = "vfx/iw7/core/zombie/pack_a_punch/vfx_zb_sj_smk"
TARGET = "vfx/iwz/directors_death_jar_red"
ZONE = "iwz_directors_death"
CURVES = {22: 1, 32: 8, 38: 2, 43: 2, 45: 6, 47: 6}
INLINE_MODULES = {0, 1, 11, 14, 17, 18, 23, 24, 28, 36}


def uint(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def red(data, offset):
    brightness = max(struct.unpack_from("<3f", data, offset))
    struct.pack_into("<3f", data, offset, brightness, brightness * .02, brightness * .01)


class JarEffect:
    def __init__(self, path):
        if path.stat().st_size != 39500:
            raise ValueError("Expected Rave's 39,500-byte soul-jar dump")
        self.data = path.read_bytes()
        self.pos = 0
        self.entries = []
        self.output = []
        self.materials = set()
        self.color_modules = 0

    def record(self, size, kind=8):
        tag = self.data[self.pos]
        self.pos += 1
        if tag == 9:  # Serialized pointer to a previous record/array element.
            index, element = struct.unpack_from("<II", self.data, self.pos)
            self.pos += 8
            start, count = self.entries[index]
            start += element * size
            count -= element
        else:
            assert tag == kind, (self.pos - 1, tag, kind)
            exists = self.data[self.pos]
            self.pos += 1
            if not exists:
                self.output.append(bytearray((kind, 0)))
                return bytearray(), 0
            if kind == 8:
                count = uint(self.data, self.pos)
                self.pos += 4
                start = self.pos
                self.pos += size * count
            else:
                start = self.pos
                self.pos = self.data.index(0, start) + 1
                count = self.pos - start
            self.entries.append((start, count))
        payload = bytearray(self.data[start:start + size * count])
        self.output.append(bytearray((kind, 1)))
        if kind == 8:
            self.output.append(bytearray(struct.pack("<I", count)))
        self.output.append(payload)
        return payload, count

    def modules(self):
        modules, count = self.record(160)
        for index in range(count):
            offset = index * 160
            module_type = struct.unpack_from("<H", modules, offset)[0]
            if module_type == 1:  # INIT_ATTRIBUTES, colorMin/colorMax; leave alpha intact.
                red(modules, offset + 64)
                red(modules, offset + 80)
                self.color_modules += 1
            if module_type == 10:  # INIT_MATERIAL
                _, assets = self.record(32)
                for _ in range(assets):
                    material, _ = self.record(1, 7)
                    self.materials.add(material[:-1].decode("ascii"))
            elif module_type in CURVES:
                curves = [self.record(16) for _ in range(CURVES[module_type])]
                if module_type == 32:  # COLOR_GRAPH: RGBA min, then RGBA max.
                    for base in (0, 4):
                        r, g, b = curves[base:base + 3]
                        assert r[1] == g[1] == b[1]
                        for point in range(r[1]):
                            pos = point * 16
                            assert r[0][pos:pos + 4] == g[0][pos:pos + 4] == b[0][pos:pos + 4]
                            brightness = max(struct.unpack_from("<f", curve[0], pos + 4)[0]
                                             for curve in (r, g, b))
                            for curve, ratio in zip((r, g, b), (1, .02, .01)):
                                struct.pack_into("<f", curve[0], pos + 4, brightness * ratio)
                    self.color_modules += 1
            else:
                assert module_type in INLINE_MODULES, module_type

    def generate(self):
        system, count = self.record(128)
        assert count == 1 and uint(system, 28) == 10 and uint(system, 32) == 0
        name, _ = self.record(1, 6)
        assert name == SOURCE.encode() + b"\0"
        name[:] = TARGET.encode() + b"\0"
        emitters, count = self.record(144)
        assert count == 10
        for index in range(count):
            states, state_count = self.record(32)
            assert state_count == uint(emitters, index * 144 + 8)
            for _ in range(state_count):
                groups, group_count = self.record(16)
                assert group_count == 3
                for _ in range(group_count):
                    self.modules()
            self.record(16)  # Emitter fade curve.
        self.record(48)  # Scripted input nodes (none in this effect).
        assert self.pos == len(self.data)
        assert self.color_modules == 19 and len(self.materials) == 4
        return b"".join(self.output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", type=Path, default=Path(
        "D:/Steam/steamapps/common/Call of Duty - Infinite Warfare/dump/cp_rave"))
    parser.add_argument("--output", type=Path, default=Path("assets/directors_death"))
    args = parser.parse_args()
    effect = JarEffect(args.dump / "particlesystem" / (SOURCE + ".iw7VFX"))
    data = effect.generate()
    target = args.output / "zonetool" / ZONE / "particlesystem" / (TARGET + ".iw7VFX")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    csv = args.output / "zone_source" / (ZONE + ".csv")
    csv.parent.mkdir(parents=True, exist_ok=True)
    csv.write_text("// Stock Rave materials are references; load this zone after cp_rave.\n" +
                   "".join(f"material,,{name}\n" for name in sorted(effect.materials)) +
                   f"vfx,{TARGET}\n", encoding="utf-8")
    print(f"[DeathWish] {target}: {len(data)} bytes, 10 emitters, "
          f"{effect.color_modules} red color modules, {len(effect.materials)} stock materials")


if __name__ == "__main__":
    main()
