"""Local Noir geometry viewer and the single JSON -> GSC placement converter."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
WEB = Path(__file__).resolve().parent
DEFAULT_GAME = Path(r"D:\Steam\steamapps\common\Call of Duty - Infinite Warfare")
LAYOUT = ROOT / "data/layouts/mp_prime.json"
SCRIPT = Path("custom_scripts/mp/maps/mp_prime/noir_layout.gsc")
PRESETS = {
    "calibration": {"label": "Reference", "symbol": "+", "color": "#f9d86b"},
    "player_spawn": {"label": "Player start / respawn", "symbol": "S", "color": "#ffffff"},
    "quick_revive": {"label": "Quick Revive · solo 500", "symbol": "QR", "color": "#74d8ff"},
    "wall_buy": {"label": "EMC · 500 points / ammo 250", "symbol": "EMC", "color": "#90efaa"},
    "power": {"label": "Power switch", "symbol": "P", "color": "#ffbd66"},
    "magic_wheel": {"label": "Magic Wheel · 950", "symbol": "MW", "color": "#cb9cff"},
    "barricade": {"label": "Barricade · hold Use to repair", "symbol": "B", "color": "#ef9797"},
    "zombie_spawn": {"label": "Zombie spawn", "symbol": "Z", "color": "#ed718c"},
}


def geometry_info(path):
    with path.open("rb") as stream:
        magic, version, length = struct.unpack("<III", stream.read(12))
        size, kind = struct.unpack("<II", stream.read(8))
        if magic != 0x46546C67 or version != 2 or kind != 0x4E4F534A or size > 1024 * 1024:
            raise ValueError("Expected the IWZ world GLB export")
        gltf = json.loads(stream.read(size))
    extras = gltf["extras"]
    if extras["baseMap"] != "mp_prime" or gltf["nodes"][0]["matrix"] != [1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1]:
        raise ValueError("Unexpected map or coordinate transform")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return {"sha256": digest.hexdigest(), "worldChecksum": extras["worldChecksum"],
            "bounds": {k: gltf["accessors"][0][k] for k in ("min", "max")},
            "triangles": gltf["accessors"][1]["count"] // 3, "coverage": extras["scope"],
            "omitted": extras["omitted"], "omittedStaticProps": extras["omittedStaticProps"]}


def validate_layout(value, geometry):
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or value.get("baseMap") != "mp_prime":
        raise ValueError("Expected version 1 layout for mp_prime")
    if value.get("geometry") != {k: geometry[k] for k in ("sha256", "worldChecksum")}:
        raise ValueError("This layout belongs to a different geometry export; load the matching world.glb")
    markers = value.get("markers")
    if not isinstance(markers, list) or len(markers) > 32:
        raise ValueError("A layout can contain up to 32 markers")
    seen, clean = set(), []
    for marker in markers:
        if not isinstance(marker, dict):
            raise ValueError("Invalid marker")
        identity, preset = marker.get("id"), marker.get("preset")
        if not isinstance(identity, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,39}", identity) or identity in seen:
            raise ValueError("Marker IDs must be unique lowercase letters, digits or underscores (40 characters maximum)")
        seen.add(identity)
        if not isinstance(preset, str) or preset not in PRESETS:
            raise ValueError(f"Unknown preset: {preset}")
        fields = {}
        for key in ("position", "normal"):
            vector = marker.get(key)
            if not isinstance(vector, list) or len(vector) != 3 or any(type(n) not in (int, float) or not math.isfinite(n) for n in vector):
                raise ValueError(f"{identity}: {key} needs three finite numbers")
            fields[key] = [round(n, 6) for n in vector]
        if any(n < geometry["bounds"]["min"][i] - 256 or n > geometry["bounds"]["max"][i] + 256 for i, n in enumerate(fields["position"])):
            raise ValueError(f"{identity}: position is outside the exported world")
        if abs(sum(n*n for n in fields["normal"]) - 1) > 0.01:
            raise ValueError(f"{identity}: surface normal must have unit length")
        yaw = marker.get("yaw")
        if type(yaw) not in (int, float) or not math.isfinite(yaw):
            raise ValueError(f"{identity}: facing needs a finite angle")
        clean.append({"id": identity, "preset": preset, **fields, "yaw": round(yaw % 360, 6)})
    if sum(marker["preset"] == "player_spawn" for marker in clean) > 1:
        raise ValueError("This solo prototype supports one player start marker")
    return {"schemaVersion": 1, "baseMap": "mp_prime", "geometry": value["geometry"], "markers": clean}


def compile_layout(layout):
    def vector(values):
        return "(" + ", ".join(f"{n:.6f}" for n in values) + ")"
    lines = ["// Generated by tools/map-viewer/server.py. Edit the JSON layout through the viewer.",
             "// IWZ-LOAD: dvar=iwz_noir_placement", "", "checksum()", "{",
             f'    return "{layout["geometry"]["worldChecksum"]}";', "}", "", "markers()", "{", "    items = [];"]
    for item in layout["markers"]:
        lines += ["    item = spawnstruct();", f'    item.id = "{item["id"]}";',
                  f'    item.preset = "{item["preset"]}";', f'    item.origin = {vector(item["position"])};',
                  f'    item.normal = {vector(item["normal"])};', f'    item.yaw = {item["yaw"]:.6f};',
                  "    items[items.size] = item;"]
    return "\n".join(lines + ["    return items;", "}", ""])


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def save_layout(value, geometry, game):
    layout = validate_layout(value, geometry)
    source = compile_layout(layout)
    # A generated script has no entrypoint; the placement runtime reads it next match.
    atomic_write(game / "iw7-mod" / SCRIPT, source)
    atomic_write(ROOT / "data/cdata" / SCRIPT, source)
    atomic_write(LAYOUT, json.dumps(layout, indent=2) + "\n")
    print(f'[IWZ][MapLayout] saved markers={len(layout["markers"])} checksum={geometry["worldChecksum"]} installed={game / "iw7-mod" / SCRIPT}', flush=True)
    return layout


def serve(game, port):
    world = game / "iw7-mod/map-data/mp_prime/world.glb"
    geometry = geometry_info(world)
    if not (WEB / "node_modules/three/build/three.module.js").is_file():
        raise RuntimeError("Run npm ci --prefix tools/map-viewer first")
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def respond(self, value, status=200):
            data = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def allowed(self, mutation=False):
            hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
            if self.headers.get("Host") not in hosts:
                self.respond({"error": "Loopback host required"}, 403)
                return False
            if mutation and self.headers.get("Origin") not in {"http://" + h for h in hosts}:
                self.respond({"error": "Save from this viewer's browser tab"}, 403)
                return False
            return True

        def do_GET(self):
            if not self.allowed():
                return
            route = unquote(urlsplit(self.path).path)
            if route == "/api/project":
                try:
                    with lock:
                        layout = validate_layout(json.loads(LAYOUT.read_text()), geometry)
                    return self.respond({"geometry": geometry, "layout": layout, "presets": PRESETS})
                except (ValueError, OSError) as error:
                    return self.respond({"error": str(error)}, 409)
            static = {"/": WEB / "index.html", "/app.js": WEB / "app.js", "/style.css": WEB / "style.css", "/world.glb": world}
            path = static.get(route)
            if route.startswith("/vendor/"):
                vendor = (WEB / "node_modules/three").resolve()
                candidate = (vendor / route.removeprefix("/vendor/")).resolve()
                if candidate.is_relative_to(vendor) and candidate.suffix == ".js":
                    path = candidate
            if path is None or not path.is_file():
                return self.respond({"error": "Not found"}, 404)
            content_type = {".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".glb": "model/gltf-binary"}.get(path.suffix, "application/octet-stream")
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(path.stat().st_size))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            with path.open("rb") as stream:
                shutil.copyfileobj(stream, self.wfile)

        def do_POST(self):
            if not self.allowed(mutation=True):
                return
            if self.path != "/api/layout":
                return self.respond({"error": "Not found"}, 404)
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 65536:
                    raise ValueError("Layout must be between 1 and 65536 bytes")
                value = json.loads(self.rfile.read(length))
                with lock:
                    layout = save_layout(value, geometry, game)
                self.respond({"layout": layout, "message": "Saved and installed. Restart the match to apply."})
            except (ValueError, OSError) as error:
                self.respond({"error": str(error)}, 400)

    print(f"[IWZ][MapLayout] http://127.0.0.1:{port} geometry={geometry['sha256']} (Ctrl+C to stop)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    serve(args.game.resolve(), args.port)
