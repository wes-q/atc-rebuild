"""
Converts original Raycrash DirectX .x files to glTF for Godot.

Reads only from the archive and writes to godot/assets/original (git-ignored).
Nothing from the archive is executed: Assimp parses the files as data.

    python3 -I godot/tools/convert_original.py <archive data dir> <output dir>

The data dir is ".../extracted/source/ATC BIN/bin/data".
"""

from __future__ import annotations

import json
import math
import pathlib
import re
import shutil
import struct
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
    ("anim/zeid_damage01.x", "zeid/zeid_damage01"),
    ("anim/zeid_damage02.x", "zeid/zeid_damage02"),
    ("anim/explo2_result.X", "fx/explo2_result"),
    ("weapon/wall_crash.X", "fx/wall_crash"),
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
    search = [src.parent, src.parent / "object", src.parent.parent, data_dir / "map" / "common", data_dir / "texture", data_dir / "texture01", data_dir / "weapon", data_dir / "anim"]
    # Map skies share textures between arenas, so the other map folders come last.
    search += sorted(d for d in (data_dir / "map").iterdir() if d.is_dir() and d not in search)
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


# --- Battle maps -----------------------------------------------------------------------------

# Arenas in room map order: page_game_room.lua handle_map_select picks the Lua table by index,
# and the server's MapNo enum uses the same order for spawn points.
MAPS = [
    ("space", "Space", "test_map"),
    ("city", "City", "city_map"),
    ("sky", "Sky", "sky_map"),
    ("gsession", "G-Session", "g_session_map"),
    ("escape", "Deep Escape", "DeepEscape"),
]
MAP_SCRIPT = "script/map/test_map.lua"
SERVER_SOURCE = "CodiNET Server Source 1/RAYCRASH_SERVER/source/RayCrash/raycrash.cpp"

HAHA_SCALE_VAL = 0.3  # rc_map::load scales the whole map model.
# rc_map::add_to_collision_mesh keeps faces whose normal is less than this aligned with +y.
WALL_NORMAL_LIMIT = 0.8
# Faces this far from the play plane can never touch a mech or a bullet, so they are left out.
PLANE_MARGIN = 60.0


def lua_table(text: str, name: str) -> dict:
    """Reads the flat fields and light values of one map table in test_map.lua."""
    m = re.search(rf"^{re.escape(name)}\s*=\s*\{{(.*?)^\}}", text, re.S | re.M)
    if not m:
        raise ValueError(f"map table {name} not found")
    body = "\n".join(line.split("--", 1)[0] for line in m.group(1).splitlines())
    out: dict = {}
    for key, val in re.findall(r"(\w+)\s*=\s*('[^']*'|-?[\d.]+)\s*,", body):
        out[key] = val.strip("'") if val.startswith("'") else float(val)
    for key, axis, val in re.findall(r"client_global\.(light_\w+)\.([xyz])\s*=\s*(-?[\d.]+)", body):
        out.setdefault(key, {})[axis] = float(val)
    return out


def server_spawns(source: pathlib.Path) -> dict[str, list[list[float]]]:
    """Start points from RayCrashServer::InitializeMsgServer: a table for the city, a circle
    of twelve for the rest. Each is (x, z) on the plane."""
    text = source.read_bytes().decode("cp949", errors="replace")
    spawns: dict[str, list[list[float]]] = {}
    city: dict[tuple[int, str], float] = {}
    for idx, axis, val in re.findall(r"map_info\[city\]\.start_point\[(\d+)\]\.(x|z)\s*=\s*(-?[\d.]+)", text):
        city[(int(idx), axis)] = float(val)
    spawns["city"] = [[city[(i, "x")], city[(i, "z")]] for i in range(12) if (i, "x") in city]
    circle = r"map_info\[(\w+)\]\.start_point\[\w+\]\.x\s*=\s*\(float\)\(cosf\(\s*\(3\.14f/6\.0f\)\s*\*\s*\(\s*\(float\)\w+\s*\+\s*9\.5f\s*\)\s*\)\s*\*\s*([\d.]+)f"
    for map_id, radius in re.findall(circle, text):
        r = float(radius)
        spawns[map_id] = [[math.cos(3.14 / 6 * (i + 9.5)) * r, math.sin(3.14 / 6 * (i + 9.5)) * r] for i in range(12)]
    return spawns


class Gltf:
    """Just enough glTF reading to walk the frame tree and pull triangles out of meshes."""

    def __init__(self, path: pathlib.Path):
        self.json = json.loads(path.read_text(encoding="utf-8"))
        self.buffers = [(path.parent / b["uri"]).read_bytes() for b in self.json.get("buffers", [])]
        self.pose = self.first_key_pose()

    def first_key_pose(self) -> dict[int, dict]:
        """Node properties at time 0 of the first animation. The engine keeps a map model's
        animation controller, so Model::update(0) poses every frame from its keys before
        rc_map collects the walls. Map keys are full matrices whose scale is often 1 where
        the frame's own matrix is not."""
        pose: dict[int, dict] = {}
        anims = self.json.get("animations", [])
        if not anims:
            return pose
        anim = anims[0]
        for ch in anim["channels"]:
            path = ch["target"]["path"]
            if path not in ("translation", "rotation", "scale"):
                continue
            first = self.accessor(anim["samplers"][ch["sampler"]]["output"])[0]
            pose.setdefault(ch["target"]["node"], {})[path] = list(first)
        return pose

    def accessor(self, index: int) -> list:
        acc = self.json["accessors"][index]
        view = self.json["bufferViews"][acc["bufferView"]]
        data = self.buffers[view["buffer"]]
        fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[acc["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
        size = struct.calcsize(fmt)
        stride = view.get("byteStride", size * width)
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        rows = [struct.unpack_from(f"<{width}{fmt}", data, base + i * stride) for i in range(acc["count"])]
        return [r[0] for r in rows] if width == 1 else rows

    def local_matrix(self, node: dict) -> list[list[float]]:
        if "matrix" in node:
            m = node["matrix"]
            return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
        t = node.get("translation", [0, 0, 0])
        x, y, z, w = node.get("rotation", [0, 0, 0, 1])
        s = node.get("scale", [1, 1, 1])
        rot = [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
        return [[rot[r][0] * s[0], rot[r][1] * s[1], rot[r][2] * s[2], t[r]] for r in range(3)] + [[0, 0, 0, 1]]

    def walk(self, root: list[list[float]]):
        """Yields (node, parent node, world matrix) for every node, parents first."""
        stack = [(i, None, root) for i in reversed(self.json["scenes"][self.json.get("scene", 0)]["nodes"])]
        while stack:
            i, parent, parent_world = stack.pop()
            node = self.json["nodes"][i]
            posed = {**node, **self.pose.get(i, {})}
            if i in self.pose:
                posed.pop("matrix", None)
            world = matmul(parent_world, self.local_matrix(posed))
            yield node, parent, world
            for c in reversed(node.get("children", [])):
                stack.append((c, node, world))

    def triangles(self, mesh_index: int):
        for prim in self.json["meshes"][mesh_index]["primitives"]:
            if prim.get("mode", 4) != 4:
                continue
            pos = self.accessor(prim["attributes"]["POSITION"])
            idx = self.accessor(prim["indices"]) if "indices" in prim else list(range(len(pos)))
            for k in range(0, len(idx) - 2, 3):
                yield pos[idx[k]], pos[idx[k + 1]], pos[idx[k + 2]]


IDENTITY = [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]


def matmul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def to_original(m: list[list[float]], v) -> tuple[float, float, float]:
    """Assimp's scene point to the original world: Assimp mirrored z on import, then the
    map's HAHA_SCALE_VAL."""
    x = m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2] + m[0][3]
    y = m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2] + m[1][3]
    z = m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2] + m[2][3]
    return (x * HAHA_SCALE_VAL, y * HAHA_SCALE_VAL, -z * HAHA_SCALE_VAL)


def collision_triangles(model: Gltf, root: list[list[float]]) -> list[float]:
    """rc_map::add_collision_mesh_itr and add_to_collision_mesh. Skips "o:" frames, frames
    whose name starts with "(", and children of a meshless "(" frame. Keeps frames whose
    bounding sphere reaches the y = 0 play plane, and of those only the steep faces."""
    out: list[float] = []
    for node, parent, world in model.walk(root):
        name = node.get("name", "")
        if name.startswith("o:") or name.startswith("("):
            continue
        if parent is not None and "mesh" not in parent and parent.get("name", "").startswith("("):
            continue
        if "mesh" not in node:
            continue
        tris = [tuple(to_original(world, v) for v in tri) for tri in model.triangles(node["mesh"])]
        points = [p for tri in tris for p in tri]
        if not points:
            continue
        # D3DXComputeBoundingSphere: centre at the vertex average, radius to the farthest.
        cx, cy, cz = (sum(p[i] for p in points) / len(points) for i in range(3))
        radius = max(math.dist((cx, cy, cz), p) for p in points)
        if radius - abs(cy) <= 0.0:
            continue
        for v0, v1, v2 in tris:
            a = [v1[i] - v0[i] for i in range(3)]
            b = [v2[i] - v0[i] for i in range(3)]
            n = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
            length = math.sqrt(sum(c * c for c in n))
            if length == 0.0 or abs(n[1] / length) >= WALL_NORMAL_LIMIT:
                continue
            ys = (v0[1], v1[1], v2[1])
            if min(ys) > PLANE_MARGIN or max(ys) < -PLANE_MARGIN:
                continue
            out.extend(round(c, 3) for p in (v0, v1, v2) for c in p)
    return out


def convert_maps(data_dir: pathlib.Path, out_dir: pathlib.Path) -> None:
    script = find_case_insensitive(data_dir, MAP_SCRIPT).read_bytes().decode("cp949", errors="replace")
    spawns = server_spawns(data_dir.parents[2] / SERVER_SOURCE)
    index = []
    for map_id, title, table in MAPS:
        props = lua_table(script, table)
        model_rel = props["map_object_file"].replace("\\", "/")
        sky_rel = props["sky_map_file"].replace("\\", "/")
        folder = f"map/{map_id}"
        convert(data_dir, out_dir, model_rel, f"{folder}/rac")
        convert(data_dir, out_dir, sky_rel, f"{folder}/skymap")

        model = Gltf(out_dir / f"{folder}/rac.gltf")
        tris = collision_triangles(model, IDENTITY)
        objects = []
        # rc_map::add_map_object_itr: an "o:name" frame places <map folder>/name.x there.
        for node, _parent, world in model.walk(IDENTITY):
            name = node.get("name", "")
            if not name.startswith("o:"):
                continue
            obj = name[2:]
            obj_rel = str(pathlib.PurePosixPath(model_rel).parent / f"{obj}.x")
            convert(data_dir, out_dir, obj_rel, f"{folder}/{obj}")
            tris += collision_triangles(Gltf(out_dir / f"{folder}/{obj}.gltf"), world)
            objects.append({"file": f"{obj}.gltf", "matrix": [world[r][c] for c in range(4) for r in range(4)]})

        info = {
            "id": map_id,
            "title": title,
            "lua_table": table,
            "model": "rac.gltf",
            "sky": "skymap.gltf",
            "objects": objects,
            "bounds": {k: props[k] for k in ("x_min_bound", "x_max_bound", "y_min_bound", "y_max_bound")},
            "light_diffuse": props.get("light_diffuse"),
            "light_ambient": props.get("light_ambient"),
            "light_direction": props.get("light_direction"),
            "spawns": [[round(x, 3), round(z, 3)] for x, z in spawns.get(map_id, [])],
            "collision": tris,
        }
        (out_dir / folder / "map.json").write_text(json.dumps(info), encoding="utf-8")
        index.append({"id": map_id, "title": title})
        print(f"{table} -> {folder}/map.json: {len(tris) // 9} wall triangles, {len(objects)} objects, {len(info['spawns'])} spawns")
    (out_dir / "map" / "maps.json").write_text(json.dumps(index, indent=1), encoding="utf-8")


def main() -> None:
    data_dir = pathlib.Path(sys.argv[1]).resolve()
    out_dir = pathlib.Path(sys.argv[2]).resolve()
    for rel, name in ASSETS:
        convert(data_dir, out_dir, rel, name)
    convert_maps(data_dir, out_dir)
    for rel, name in TEXTURES:
        src = find_case_insensitive(data_dir, rel)
        (out_dir / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, out_dir / name)
        print(f"{rel} -> {name}")


if __name__ == "__main__":
    main()
