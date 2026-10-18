"""
Converts original Raycrash DirectX .x files to glTF for Godot.

Reads only from the archive and writes to godot/assets/original (git-ignored).
Nothing from the archive is executed: Assimp parses the files as data.

    python3 -I godot/tools/convert_original.py <archive data dir> <output dir>

The data dir is ".../extracted/source/ATC BIN/bin/data".
"""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys

# (source path relative to the data dir, output name)
ASSETS = [
    ("middle_character/zeid/zeid_model_middle.x", "zeid/zeid_model"),
    ("middle_character/zeid/zeid_weapon02_middle.x", "zeid/zeid_weapon02"),
    ("middle_character/zeid/zeid_weapon02_move_middle.x", "zeid/zeid_weapon02_move"),
    ("anim/zeid2.X", "zeid/rifle_sr3"),
    ("weapon/bullet_zeid2.X", "zeid/bullet_sr3"),
    ("weapon/bullet_zeid_boom.X", "zeid/bullet_sr3_boom"),
    ("map/b_map01/skymap.X", "map/b_map01_skymap"),
    ("anim/zeid_damage01.x", "zeid/zeid_damage01"),
    ("anim/zeid_damage02.x", "zeid/zeid_damage02"),
    ("anim/explo2_result.X", "fx/explo2_result"),
]

IMAGE_TYPES = {".png", ".jpg", ".jpeg"}

# Colour schemes swapped onto the model at runtime (character_mapping_parameter.lua).
TEXTURES = [
    ("item02/armor/color/zeid/zeid_p01.png", "zeid/zeid_p01.png"),
    ("item02/armor/color/zeid/zeid_p02.png", "zeid/zeid_p02.png"),
]


def find_case_insensitive(base: pathlib.Path, rel: str) -> pathlib.Path:
    """The archive mixes .x and .X, so match each path segment ignoring case."""
    cur = base
    for part in pathlib.PurePosixPath(rel).parts:
        hit = next((p for p in cur.iterdir() if p.name.lower() == part.lower()), None)
        if hit is None:
            raise FileNotFoundError(base / rel)
        cur = hit
    return cur


def find_texture(name: str, search_dirs: list[pathlib.Path]) -> pathlib.Path | None:
    for d in search_dirs:
        for p in d.iterdir():
            if p.is_file() and p.name.lower() == name.lower():
                return p
    return None


def to_png(src: pathlib.Path, dst: pathlib.Path) -> None:
    if src.suffix.lower() in IMAGE_TYPES:
        shutil.copyfile(src, dst.with_suffix(src.suffix.lower()))
        return
    # BMP, TGA and DDS go through macOS's image tool.
    subprocess.run(["sips", "-s", "format", "png", str(src), "--out", str(dst)], check=True, capture_output=True)


# Binary .x data object "AnimTicksPerSecond { 4800 }", as written by the exporter in files
# that have one (zeid_weapon02_middle.x). Some files omit it, and Assimp then writes
# invalid key times. 4800 is the 3ds Max exporter default and matches the clip lengths.
TICKS_INSTANCE = (
    b"\x01\x00\x12\x00\x00\x00AnimTicksPerSecond"
    b"\x0a\x00\x06\x00\x01\x00\x00\x00\xc0\x12\x00\x00\x0b\x00"
)


def with_tick_rate(src: pathlib.Path, work: pathlib.Path) -> pathlib.Path:
    data = src.read_bytes()
    if b"AnimationSet" not in data or not data.startswith(b"xof 0303bin"):
        return src
    if b"AnimTicksPerSecond\x0a\x00\x06\x00" in data:
        return src
    work.mkdir(parents=True, exist_ok=True)
    patched = work / src.name
    patched.write_bytes(data[:16] + TICKS_INSTANCE + data[16:])
    return patched


def convert(data_dir: pathlib.Path, out_dir: pathlib.Path, rel: str, out_name: str) -> None:
    src = find_case_insensitive(data_dir, rel)
    out = out_dir / f"{out_name}.gltf"
    out.parent.mkdir(parents=True, exist_ok=True)
    work = out_dir / ".work"
    readable = with_tick_rate(src, work)
    subprocess.run(["assimp", "export", str(readable), str(out), "-fgltf2"], check=True, capture_output=True)
    if readable != src:
        readable.unlink()
        print(f"  {rel}: added the missing 4800 ticks-per-second declaration")

    # Texture URIs carry the artists' old Windows paths in CP949. Decode bytes leniently,
    # then point each image at a real file found next to the model or in the texture folders.
    raw = out.read_bytes().decode("utf-8", errors="replace")
    gltf = json.loads(raw)
    search = [src.parent, src.parent / "object", data_dir / "map" / "common", data_dir / "texture", data_dir / "texture01", data_dir / "weapon", data_dir / "anim"]
    for img in gltf.get("images", []):
        uri = img.get("uri", "")
        if uri.startswith("data:"):
            continue
        base = uri.replace("\\", "/").split("/")[-1]
        tex = find_texture(base, [d for d in search if d.is_dir()])
        if tex is None:
            # Old path did not survive decoding: try the ASCII tail after the last separator.
            tail = base.split("�")[-1].strip()
            tex = find_texture(tail, [d for d in search if d.is_dir()]) if tail else None
        if tex is None:
            print(f"  missing texture for {out_name}: {base!r}")
            img["uri"] = ""
            continue
        stem = tex.stem.replace(" ", "_")
        dst = out.parent / f"{stem}.png"
        to_png(tex, dst)
        final = dst if dst.exists() else dst.with_suffix(tex.suffix.lower())
        img["uri"] = final.name
        print(f"  texture {tex.name} -> {final.name}")

    # Assimp writes an empty animation for static files and names every clip "anim".
    # Drop the empty ones and number the rest, since the original engine picks clips by index.
    kept = []
    for anim in gltf.get("animations", []):
        inputs = [gltf["accessors"][s["input"]] for s in anim["samplers"]]
        if not inputs or any(acc.get("count", 0) == 0 or acc["max"][0] < acc["min"][0] for acc in inputs):
            continue
        anim["name"] = f"anim_{len(kept)}"
        kept.append(anim)
    if kept:
        gltf["animations"] = kept
    else:
        gltf.pop("animations", None)

    out.write_text(json.dumps(gltf, ensure_ascii=False, indent=1), encoding="utf-8")
    anims = [(a.get("name"), len(a["channels"])) for a in gltf.get("animations", [])]
    print(f"{rel} -> {out.relative_to(out_dir)}: {len(gltf['nodes'])} nodes, animations {anims}")


def main() -> None:
    data_dir = pathlib.Path(sys.argv[1]).resolve()
    out_dir = pathlib.Path(sys.argv[2]).resolve()
    for rel, name in ASSETS:
        convert(data_dir, out_dir, rel, name)
    for rel, name in TEXTURES:
        src = find_case_insensitive(data_dir, rel)
        (out_dir / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, out_dir / name)
        print(f"{rel} -> {name}")


if __name__ == "__main__":
    main()
