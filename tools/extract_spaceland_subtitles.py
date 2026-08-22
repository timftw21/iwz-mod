#!/usr/bin/env python3
"""Extract Spaceland character VO and build per-audio subtitle definitions."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path


SAB_MAGIC = 0x23585532
SAB_VERSION = 4
SAB_HEADER = struct.Struct("<6I8s3Q")
SAB_AUDIO_ENTRY_SIZE = 44
SAB_AUDIO_FORMAT_FLAC = 8
SPACELAND_SOUND_BANKS = {"cp_zmb.english", "patch_cp_zmb.english"}
GENERATED_AUDIO_RE = re.compile(r"^[0-9a-f]{8}__.+\.flac$", re.IGNORECASE)
STRING_LITERAL_RE = re.compile(r'"((?:\\.|[^"\\])*)"')
VOICE_CALL_RE = re.compile(
    r"try_to_play_vo(?:_on_all_players)?\s*\(\s*\"([^\"]+)\"",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Character:
    speaker: str
    asset_prefix: str
    directory: str
    color_code: str


CHARACTERS = (
    Character("Sally", "cp\\vg\\", "sally", "^2"),
    Character("Poindexter", "cp\\nd\\", "poindexter", "^2"),
    Character("Andre", "cp\\rp\\", "andre", "^2"),
    Character("A.J.", "cp\\jk\\", "aj", "^2"),
    Character("David Hasselhoff", "cp\\dj\\", "david_hasselhoff", "^2"),
    Character("Willard Wyler", "cp\\ww\\", "willard_wyler", "^1"),
    Character("N3IL", "cp\\n31l\\", "n3il", "^2"),
)


@dataclass
class AudioDefinition:
    asset: str
    character: Character
    aliases: set[str] = field(default_factory=set)
    sound_banks: set[str] = field(default_factory=set)


@dataclass(frozen=True)
class SabEntry:
    bank: Path
    key: int
    size: int
    seek_table_size: int
    frame_count: int
    hybrid_pcm_size: int
    offset: int
    frame_rate: int
    channel_count: int
    format: int


def sound_hash(name: str) -> int:
    value = 5381
    for byte in name.lower().encode("utf-8"):
        value = (65599 * value + byte) & 0xFFFFFFFF
    return value or 1


def normalize_asset(asset: str) -> str:
    return asset.strip().replace("/", "\\")


def select_character(asset: str) -> Character | None:
    lowered = asset.lower()
    for character in CHARACTERS:
        if lowered.startswith(character.asset_prefix):
            return character
    return None


def read_alias_dump(path: Path) -> dict[str, AudioDefinition]:
    definitions: dict[str, AudioDefinition] = {}

    with path.open("r", encoding="utf-8-sig", newline="") as input_file:
        reader = csv.DictReader(input_file)
        expected = {"sound_bank", "alias", "audio_asset"}
        if not reader.fieldnames or not expected.issubset(reader.fieldnames):
            raise RuntimeError(f"{path} is missing columns: {sorted(expected)}")

        for row in reader:
            sound_bank = row["sound_bank"].strip()
            if sound_bank.lower() not in SPACELAND_SOUND_BANKS:
                continue

            asset = normalize_asset(row["audio_asset"])
            character = select_character(asset)
            if character is None:
                continue

            key = asset.lower()
            definition = definitions.get(key)
            if definition is None:
                definition = AudioDefinition(asset=asset, character=character)
                definitions[key] = definition
            elif definition.character != character:
                raise RuntimeError(f"audio asset maps to multiple characters: {asset}")

            alias = row["alias"].strip()
            if alias:
                definition.aliases.add(alias)
            if sound_bank:
                definition.sound_banks.add(sound_bank)

    if not definitions:
        raise RuntimeError(f"no Spaceland character audio was found in {path}")

    hashes: dict[int, str] = {}
    for key, definition in definitions.items():
        asset_hash = sound_hash(definition.asset)
        collision = hashes.get(asset_hash)
        if collision is not None and collision != key:
            raise RuntimeError(
                f"sound hash collision 0x{asset_hash:08X}: "
                f"{definitions[collision].asset} and {definition.asset}"
            )
        hashes[asset_hash] = key

    return definitions


def read_vo_events(path: Path) -> set[str]:
    events: set[str] = set()
    with path.open("r", encoding="utf-8-sig", newline="") as input_file:
        for row in csv.reader(input_file):
            if len(row) < 2:
                continue
            event = row[1].strip().lower()
            if event:
                events.add(event)

    if not events:
        raise RuntimeError(f"no VO events were found in {path}")
    return events


def iter_spaceland_scripts(gsc_root: Path):
    for path in gsc_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".gsc", ".csc"}:
            continue

        relative_parts = [part.lower() for part in path.relative_to(gsc_root).parts]
        if "maps" in relative_parts:
            maps_index = relative_parts.index("maps")
            if len(relative_parts) <= maps_index + 1 or relative_parts[maps_index + 1] != "cp_zmb":
                continue
        yield path


def read_gsc_references(gsc_root: Path) -> tuple[set[str], set[str], int]:
    literal_aliases: set[str] = set()
    voice_events: set[str] = set()
    source_count = 0

    for path in iter_spaceland_scripts(gsc_root):
        source_count += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        literal_aliases.update(
            match.group(1).lower() for match in STRING_LITERAL_RE.finditer(text)
        )
        voice_events.update(
            match.group(1).strip().lower() for match in VOICE_CALL_RE.finditer(text)
        )

    if not source_count:
        raise RuntimeError(f"no Spaceland GSC sources were found under {gsc_root}")
    return literal_aliases, voice_events, source_count


def alias_event(alias: str) -> str:
    event = alias.lower()
    event = re.sub(r"^p[1-6]_", "", event)
    event = re.sub(r"^plr_", "", event)
    event = re.sub(r"_r$", "", event)
    return event


def filter_reachable_definitions(
    definitions: dict[str, AudioDefinition], vo_table: Path, gsc_root: Path
) -> dict[str, AudioDefinition]:
    vo_events = read_vo_events(vo_table)
    literal_aliases, gsc_voice_events, source_count = read_gsc_references(gsc_root)
    reachable_events = vo_events | gsc_voice_events

    reachable: dict[str, AudioDefinition] = {}
    aliases_used: set[str] = set()
    aliases_ignored: set[str] = set()
    for key, definition in definitions.items():
        matched_aliases = {
            alias
            for alias in definition.aliases
            if alias.lower() in literal_aliases
            or alias_event(alias) in reachable_events
        }
        if matched_aliases:
            reachable[key] = definition
            aliases_used.update(alias.lower() for alias in matched_aliases)
        else:
            aliases_ignored.update(alias.lower() for alias in definition.aliases)

    print(
        f"Reachability: {len(vo_events)} VO-table events, "
        f"{len(gsc_voice_events)} direct VO calls, {source_count} GSC/CSC sources"
    )
    print(
        f"Reachability retained {len(reachable)} of {len(definitions)} audio assets "
        f"({len(aliases_used)} aliases); ignored {len(definitions) - len(reachable)} "
        f"unreferenced assets ({len(aliases_ignored)} aliases)"
    )
    if not reachable:
        raise RuntimeError("the reachability filter rejected every audio asset")
    return reachable


def iter_sab_files(game_root: Path):
    files = list(game_root.rglob("*.sabl"))
    files.extend(game_root.rglob("*.sabs"))
    yield from sorted(files, key=lambda path: str(path).lower())


def scan_sab_entries(
    game_root: Path, requested_hashes: set[int]
) -> dict[int, list[SabEntry]]:
    matches: dict[int, list[SabEntry]] = defaultdict(list)
    scanned_files = 0

    for bank in iter_sab_files(game_root):
        scanned_files += 1
        with bank.open("rb") as input_file:
            header_data = input_file.read(SAB_HEADER.size)
            if len(header_data) != SAB_HEADER.size:
                continue

            (
                magic,
                version,
                audio_entry_size,
                _hash_entry_size,
                _name_entry_size,
                entry_count,
                _unknown,
                declared_size,
                entry_table_offset,
                _hash_table_offset,
            ) = SAB_HEADER.unpack(header_data)

            actual_size = bank.stat().st_size
            if magic != SAB_MAGIC or version != SAB_VERSION:
                continue
            if audio_entry_size < SAB_AUDIO_ENTRY_SIZE:
                raise RuntimeError(
                    f"unsupported SAB audio entry size {audio_entry_size}: {bank}"
                )
            if entry_count == 0:
                continue
            if declared_size > actual_size or entry_table_offset >= actual_size:
                raise RuntimeError(f"invalid SAB offsets: {bank}")

            input_file.seek(entry_table_offset)
            table_size = entry_count * audio_entry_size
            table = input_file.read(table_size)
            if len(table) != table_size:
                raise RuntimeError(f"truncated SAB entry table: {bank}")

            for index in range(entry_count):
                offset = index * audio_entry_size
                key = struct.unpack_from("<I", table, offset)[0]
                if key not in requested_hashes:
                    continue

                size, seek_size, frame_count, hybrid_size = struct.unpack_from(
                    "<4I", table, offset + 4
                )
                audio_offset = struct.unpack_from("<Q", table, offset + 20)[0]
                frame_rate = struct.unpack_from("<I", table, offset + 28)[0]
                channel_count = table[offset + 32]
                audio_format = table[offset + 34]

                if audio_offset + seek_size + size + hybrid_size > actual_size:
                    raise RuntimeError(f"invalid audio payload offset in {bank}")

                matches[key].append(
                    SabEntry(
                        bank=bank,
                        key=key,
                        size=size,
                        seek_table_size=seek_size,
                        frame_count=frame_count,
                        hybrid_pcm_size=hybrid_size,
                        offset=audio_offset,
                        frame_rate=frame_rate,
                        channel_count=channel_count,
                        format=audio_format,
                    )
                )

    print(
        f"Scanned {scanned_files} SAB files; located "
        f"{len(matches)} of {len(requested_hashes)} requested hashes"
    )
    return matches


def candidate_score(definition: AudioDefinition, entry: SabEntry) -> tuple[int, str]:
    stem = entry.bank.stem.lower()
    has_patch_alias = any(bank.lower().startswith("patch_cp_zmb") for bank in definition.sound_banks)
    is_complete_bank = entry.bank.suffix.lower() == ".sabs"

    if is_complete_bank and has_patch_alias and stem == "eng_patch_cp_zmb":
        score = 0
    elif is_complete_bank and stem == "eng_code_post_gfx":
        score = 1
    elif is_complete_bank and "cp_zmb" in stem and entry.bank.parent.name.lower() == "english":
        score = 2
    elif is_complete_bank and entry.bank.parent.name.lower() == "english":
        score = 3
    elif stem == "eng_cp_zmb":
        score = 4
    elif entry.bank.parent.name.lower() == "english":
        score = 5
    else:
        score = 6

    return score, str(entry.bank).lower()


def choose_entries(
    definitions: dict[str, AudioDefinition], candidates: dict[int, list[SabEntry]]
) -> dict[str, SabEntry]:
    selected: dict[str, SabEntry] = {}
    missing: list[str] = []

    for key, definition in definitions.items():
        asset_hash = sound_hash(definition.asset)
        entries = candidates.get(asset_hash, [])
        if not entries:
            missing.append(definition.asset)
            continue

        entry = min(entries, key=lambda item: candidate_score(definition, item))
        if entry.format != SAB_AUDIO_FORMAT_FLAC:
            raise RuntimeError(
                f"audio asset is not FLAC (format {entry.format}): {definition.asset}"
            )
        if not entry.frame_rate or not entry.channel_count or not entry.frame_count:
            raise RuntimeError(f"audio asset has invalid stream metadata: {definition.asset}")
        selected[key] = entry

    if missing:
        preview = "\n".join(f"  {asset}" for asset in missing[:20])
        raise RuntimeError(
            f"could not locate {len(missing)} audio assets in installed SAB files:\n{preview}"
        )

    return selected


def make_streaminfo(entry: SabEntry) -> bytes:
    header = bytearray(34)
    struct.pack_into(">HH", header, 0, 0x400, 0x400)
    flags = (
        (entry.frame_rate << 44)
        | ((entry.channel_count - 1) << 41)
        | ((16 - 1) << 36)
        | entry.frame_count
    )
    header[10:18] = flags.to_bytes(8, "big")
    return bytes(header)


def metadata_header(block_type: int, length: int, is_last: bool) -> bytes:
    return bytes(((0x80 if is_last else 0) | block_type,)) + length.to_bytes(3, "big")


def safe_leaf(asset: str) -> str:
    leaf = re.split(r"[\\/]", asset)[-1]
    leaf = re.sub(r"[<>:\"/\\|?*\x00-\x1F]", "_", leaf).rstrip(" .")
    return (leaf or "sound")[:88]


def output_filename(definition: AudioDefinition) -> str:
    return f"{sound_hash(definition.asset):08x}__{safe_leaf(definition.asset)}.flac"


def expected_flac_size(entry: SabEntry) -> int:
    seek_metadata_size = 4 + entry.seek_table_size if entry.seek_table_size else 0
    return 42 + seek_metadata_size + entry.size


def extract_raw_flac(entry: SabEntry, output_path: Path) -> None:
    with entry.bank.open("rb") as input_file, output_path.open("wb") as output_file:
        input_file.seek(entry.offset)
        seek_table = input_file.read(entry.seek_table_size)
        frames = input_file.read(entry.size)
        if len(seek_table) != entry.seek_table_size or len(frames) != entry.size:
            raise RuntimeError(f"truncated audio payload in {entry.bank}")

        output_file.write(b"fLaC")
        output_file.write(metadata_header(0, 34, not seek_table))
        output_file.write(make_streaminfo(entry))
        if seek_table:
            output_file.write(metadata_header(3, len(seek_table), True))
            output_file.write(seek_table)
        output_file.write(frames)

    if output_path.stat().st_size != expected_flac_size(entry):
        raise RuntimeError(f"unexpected extracted FLAC size: {output_path}")


def validate_flac(
    path: Path, expected_entry: SabEntry | None = None, require_normalized: bool = False
) -> None:
    with path.open("rb") as input_file:
        if input_file.read(4) != b"fLaC":
            raise RuntimeError(f"invalid FLAC marker: {path}")

        found_streaminfo = False
        found_vorbis_comment = False
        sample_rate = 0
        channel_count = 0
        frame_count = 0
        while True:
            block_header = input_file.read(4)
            if len(block_header) != 4:
                raise RuntimeError(f"truncated FLAC metadata: {path}")
            is_last = bool(block_header[0] & 0x80)
            block_type = block_header[0] & 0x7F
            block_size = int.from_bytes(block_header[1:4], "big")
            block = input_file.read(block_size)
            if len(block) != block_size:
                raise RuntimeError(f"truncated FLAC metadata block: {path}")
            if block_type == 0:
                found_streaminfo = block_size == 34
                if found_streaminfo:
                    packed = int.from_bytes(block[10:18], "big")
                    sample_rate = packed >> 44
                    channel_count = ((packed >> 41) & 0x7) + 1
                    frame_count = packed & ((1 << 36) - 1)
            elif block_type == 4:
                found_vorbis_comment = True
            if is_last:
                break

        frame_header = input_file.read(2)
        if not found_streaminfo or len(frame_header) != 2:
            raise RuntimeError(f"missing FLAC stream data: {path}")
        if frame_header[0] != 0xFF or frame_header[1] & 0xFE != 0xF8:
            raise RuntimeError(f"invalid FLAC frame sync: {path}")
        if require_normalized and not found_vorbis_comment:
            raise RuntimeError(f"FLAC was not normalized by FFmpeg: {path}")
        if expected_entry is not None and (
            sample_rate != expected_entry.frame_rate
            or channel_count != expected_entry.channel_count
            or frame_count != expected_entry.frame_count
        ):
            raise RuntimeError(
                f"normalized FLAC metadata changed for {path}: "
                f"{sample_rate} Hz, {channel_count} channels, {frame_count} frames"
            )


def extract_flac(entry: SabEntry, output_path: Path, ffmpeg: Path) -> bool:
    if output_path.is_file():
        try:
            validate_flac(output_path, entry, require_normalized=True)
            return False
        except RuntimeError:
            pass

    output_path.parent.mkdir(parents=True, exist_ok=True)
    raw_path = output_path.with_suffix(output_path.suffix + ".raw.tmp")
    normalized_path = output_path.with_suffix(output_path.suffix + ".normalized.tmp")
    raw_path.unlink(missing_ok=True)
    normalized_path.unlink(missing_ok=True)

    try:
        extract_raw_flac(entry, raw_path)
        result = subprocess.run(
            [
                str(ffmpeg),
                "-nostdin",
                "-hide_banner",
                "-loglevel",
                "error",
                "-threads",
                "1",
                "-y",
                "-i",
                str(raw_path),
                "-map_metadata",
                "-1",
                "-c:a",
                "flac",
                "-compression_level",
                "5",
                "-f",
                "flac",
                str(normalized_path),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode:
            detail = result.stderr.strip() or f"exit code {result.returncode}"
            raise RuntimeError(f"FFmpeg failed for {output_path}: {detail}")

        validate_flac(normalized_path, entry, require_normalized=True)
        normalized_path.replace(output_path)
        return True
    finally:
        raw_path.unlink(missing_ok=True)
        normalized_path.unlink(missing_ok=True)


def prune_generated_audio(
    audio_root: Path, expected_paths: set[Path]
) -> tuple[int, int]:
    expected = {path.resolve() for path in expected_paths}
    removed_count = 0
    removed_bytes = 0
    for character in CHARACTERS:
        directory = audio_root / character.directory
        if not directory.is_dir():
            continue
        for path in directory.glob("*.flac"):
            if not GENERATED_AUDIO_RE.fullmatch(path.name) or path.resolve() in expected:
                continue
            removed_bytes += path.stat().st_size
            path.unlink()
            removed_count += 1
    return removed_count, removed_bytes


def load_existing_text(json_path: Path) -> dict[str, str]:
    if not json_path.is_file():
        return {}

    with json_path.open("r", encoding="utf-8") as input_file:
        data = json.load(input_file)
    if not isinstance(data, dict):
        raise RuntimeError(f"existing subtitle file must contain an object: {json_path}")

    result: dict[str, str] = {}
    for key, value in data.items():
        if key.startswith("_") or not isinstance(value, dict):
            continue
        text = value.get("text")
        asset = value.get("asset", key)
        if isinstance(text, str) and isinstance(asset, str):
            result[asset.lower()] = text
    return result


def build_json(
    game_root: Path,
    definitions: dict[str, AudioDefinition],
    selected_entries: dict[str, SabEntry],
    audio_root: Path,
    json_path: Path,
) -> None:
    existing_text = load_existing_text(json_path)
    output: dict[str, object] = {
        "_map": "Zombies in Spaceland",
        "_entry_key": "audio asset path",
        "_audio_root": "audio/spaceland",
    }

    ordered = sorted(
        definitions.items(),
        key=lambda item: (
            CHARACTERS.index(item[1].character),
            item[1].asset.lower(),
        ),
    )
    for key, definition in ordered:
        entry = selected_entries[key]
        audio_path = audio_root / definition.character.directory / output_filename(definition)
        relative_audio = (
            Path("audio/spaceland")
            / definition.character.directory
            / output_filename(definition)
        ).as_posix()
        relative_bank = entry.bank.relative_to(game_root).as_posix()
        default_text = (
            f"{definition.character.color_code}{definition.character.speaker}^7: PLACEHOLDER"
        )

        output[definition.asset] = {
            "speaker": definition.character.speaker,
            "aliases": sorted(definition.aliases, key=str.lower),
            "asset": definition.asset,
            "audio": relative_audio,
            "source_bank": relative_bank,
            "text": existing_text.get(key, default_text),
        }

    json_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = json_path.with_suffix(json_path.suffix + ".tmp")
    with temporary_path.open("w", encoding="utf-8", newline="\n") as output_file:
        json.dump(output, output_file, ensure_ascii=False, indent=2)
        output_file.write("\n")
    temporary_path.replace(json_path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", required=True, type=Path)
    parser.add_argument("--alias-csv", required=True, type=Path)
    parser.add_argument("--vo-table", required=True, type=Path)
    parser.add_argument("--gsc-root", required=True, type=Path)
    parser.add_argument("--audio-root", required=True, type=Path)
    parser.add_argument("--json", required=True, type=Path)
    parser.add_argument("--ffmpeg", type=Path)
    parser.add_argument("--workers", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--no-prune", action="store_true")
    return parser.parse_args()


def resolve_ffmpeg(requested: Path | None) -> Path:
    if requested is not None:
        executable = requested.resolve()
    else:
        found = shutil.which("ffmpeg")
        if not found:
            raise RuntimeError("FFmpeg was not found; pass its path with --ffmpeg")
        executable = Path(found).resolve()
    if not executable.is_file():
        raise RuntimeError(f"FFmpeg does not exist: {executable}")
    return executable


def main() -> int:
    args = parse_args()
    game_root = args.game_root.resolve()
    alias_csv = args.alias_csv.resolve()
    vo_table = args.vo_table.resolve()
    gsc_root = args.gsc_root.resolve()
    audio_root = args.audio_root.resolve()
    json_path = args.json.resolve()
    ffmpeg = resolve_ffmpeg(args.ffmpeg)

    if not game_root.is_dir():
        raise RuntimeError(f"game root does not exist: {game_root}")
    if not alias_csv.is_file():
        raise RuntimeError(f"sound alias dump does not exist: {alias_csv}")
    if not vo_table.is_file():
        raise RuntimeError(f"Spaceland VO table does not exist: {vo_table}")
    if not gsc_root.is_dir():
        raise RuntimeError(f"GSC root does not exist: {gsc_root}")
    if args.workers < 1:
        raise RuntimeError("--workers must be at least 1")

    definitions = read_alias_dump(alias_csv)
    definitions = filter_reachable_definitions(definitions, vo_table, gsc_root)
    counts = defaultdict(int)
    for definition in definitions.values():
        counts[definition.character.speaker] += 1
    for character in CHARACTERS:
        print(f"{character.speaker}: {counts[character.speaker]} unique audio assets")

    requested_hashes = {sound_hash(definition.asset) for definition in definitions.values()}
    candidates = scan_sab_entries(game_root, requested_hashes)
    selected_entries = choose_entries(definitions, candidates)

    work: list[tuple[SabEntry, Path]] = []
    expected_paths: set[Path] = set()
    for key, definition in definitions.items():
        output_path = audio_root / definition.character.directory / output_filename(definition)
        expected_paths.add(output_path)
        work.append((selected_entries[key], output_path))

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        results = list(
            executor.map(
                lambda item: extract_flac(item[0], item[1], ffmpeg),
                work,
            )
        )
    extracted = sum(results)
    existing = len(results) - extracted

    build_json(game_root, definitions, selected_entries, audio_root, json_path)
    removed_count = 0
    removed_bytes = 0
    if not args.no_prune:
        removed_count, removed_bytes = prune_generated_audio(audio_root, expected_paths)
    print(
        f"Extracted {extracted} audio files; reused {existing}; "
        f"wrote {len(definitions)} definitions to {json_path}"
    )
    if not args.no_prune:
        print(
            f"Pruned {removed_count} unreferenced generated files "
            f"({removed_bytes / (1024 * 1024):.1f} MiB)"
        )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
