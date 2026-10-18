"""
Reads the original battle HUD's window definitions (script/res/*.lua) as data and copies
the art they use.

The Lua files are parsed, never run: a small reader understands table constructors,
strings, numbers and names, and skips functions. Tables refer to each other by name
(a window's texture table, for example); those references are inlined.

    python3 -I godot/tools/extract_ui.py <archive data dir> <output dir>

Writes <output dir>/ui/windows.json and the images under <output dir>/ui/, all git-ignored.
"""

from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys

# Dialogs page_game_fight:create() builds for a battle, plus the ready and go banners.
ROOT_PREFIXES = ("res_dlg_game_fight", "texture_dlg_game_fight")
SOURCES = ["script/res", "script/page/page_game_fight.lua", "script/page/page_number_show.lua",
           "script/main.lua"]
# Drawn from C++ rather than a window table: Radar::init and the low-health warning.
EXTRA_IMAGES = [
    "ui/widget/game_fight/rader/hood_player_enemy.png",
    "ui/widget/game_fight/rader/hood_player_enemy_far.PNG",
    "ui/widget/game_fight/rader/hood_player_friend.png",
    "ui2/game_fight/SPAttack.png",
    # Lock-on markers (Radar::render_lock_on_system) and the dagger's trail (Weapon28_mode1).
    "ui/widget/game_fight/rader/fughtui_lockon.PNG",
    "ui/widget/game_fight/rader/fughtui_lockon_hud.png",
    "ui/widget/game_fight/rader/fughtui_locked.PNG",
    "ui/widget/game_fight/rader/fughtui_locking.PNG",
    "texture/zeid_sword_jan02.BMP",
    # The front end's art named in script code rather than tables: the highlight glow, the
    # animated cursor (page_login_new), the loading screen (Loading_window_create) and the
    # exit picture (I_robot_img_show).
    "ui/widget/selectlight.PNG",
    "ui/widget/test/cursor01.PNG", "ui/widget/test/cursor02.PNG", "ui/widget/test/cursor03.PNG",
    "ui/widget/test/cursor04.PNG", "ui/widget/test/cursor05.PNG", "ui/widget/test/cursor06.PNG",
    "ui3/loading/loading.png", "ui3/loading/x-259-y-443.png", "ui3/loading/x-264 y459.png",
    "ui3/loading/intro.png",
]

TOKEN = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<lcomment>--\[\[.*?\]\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[\[.*?\]\])
  | (?P<string>'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")
  | (?P<number>\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)
  | (?P<name>[A-Za-z_][A-Za-z_0-9]*)
  | (?P<op>==|~=|<=|>=|\.\.|[-+*/%^#<>=(){}\[\];:,.])
    """,
    re.S | re.X,
)

BLOCK_OPEN = {"function", "if", "do", "for", "while"}


def tokenize(text: str) -> list[tuple[str, str]]:
    out = []
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            pos += 1  # stray byte from a broken CP949 decode
            continue
        kind = m.lastgroup
        pos = m.end()
        if kind in ("ws", "comment", "lcomment"):
            continue
        val = m.group()
        if kind == "string":
            val = val[1:-1].replace("\\\\", "\\").replace("\\'", "'").replace('\\"', '"')
        elif kind == "lstring":
            kind, val = "string", val[2:-2]
        out.append((kind, val))
    return out


class Parser:
    def __init__(self, tokens: list[tuple[str, str]]):
        self.t = tokens
        self.i = 0

    def peek(self, k: int = 0) -> tuple[str, str]:
        return self.t[self.i + k] if self.i + k < len(self.t) else ("eof", "")

    def next(self) -> tuple[str, str]:
        tok = self.peek()
        self.i += 1
        return tok

    def skip_block(self) -> None:
        """Skips from a block keyword to its matching end."""
        depth = 0
        while self.peek()[0] != "eof":
            kind, val = self.next()
            if kind == "name" and val in BLOCK_OPEN:
                # "while x do" and "for ... do" open one block, not two.
                if val in ("while", "for"):
                    while not (self.peek() == ("name", "do")):
                        self.next()
                    self.next()
                depth += 1
            elif kind == "name" and val == "repeat":
                depth += 1
            elif kind == "name" and val in ("end", "until"):
                depth -= 1
                if depth == 0:
                    return

    def value(self):
        kind, val = self.peek()
        if kind == "op" and val == "{":
            return self.table()
        if kind == "name" and val == "function":
            self.skip_block()
            return None
        left = self.primary()
        while self.peek()[0] == "op" and self.peek()[1] in "+-*/" and self.peek()[1] != "":
            op = self.next()[1]
            right = self.primary()
            if isinstance(left, (int, float)) and isinstance(right, (int, float)):
                left = {"+": left + right, "-": left - right, "*": left * right, "/": left / right if right else 0}[op]
            else:
                left = None
        return left

    def primary(self):
        kind, val = self.next()
        if kind == "op" and val == "-":
            v = self.primary()
            return -v if isinstance(v, (int, float)) else None
        if kind == "op" and val == "(":
            v = self.value()
            self.next()
            return v
        if kind == "number":
            f = float(val)
            return int(f) if f.is_integer() else f
        if kind == "string":
            return val
        if kind == "name":
            if val in ("nil", "true", "false"):
                return {"nil": None, "true": True, "false": False}[val]
            ref = val
            # a.b.c and calls are kept as plain references
            while self.peek()[0] == "op" and self.peek()[1] in (".", ":"):
                self.next()
                ref += "." + self.next()[1]
            if self.peek() == ("op", "("):
                depth = 0
                while True:
                    k, v = self.next()
                    if v == "(":
                        depth += 1
                    elif v == ")":
                        depth -= 1
                        if depth == 0:
                            break
                return None
            return {"@ref": ref}
        return None

    def table(self):
        self.next()  # {
        named: dict = {}
        order: list[str] = []
        items: list = []
        while True:
            kind, val = self.peek()
            if kind == "eof":
                break
            if kind == "op" and val == "}":
                self.next()
                break
            if kind == "op" and val in (",", ";"):
                self.next()
                continue
            if kind == "name" and self.peek(1) == ("op", "="):
                self.next()
                self.next()
                v = self.value()
                if val not in named:
                    order.append(val)
                named[val] = v
                continue
            if kind == "op" and val == "[":
                self.next()
                key = self.value()
                self.next()  # ]
                self.next()  # =
                named[str(key)] = self.value()
                order.append(str(key))
                continue
            items.append(self.value())
        if named:
            out = {k: named[k] for k in order}
            if items:
                out["@list"] = items
            out["@order"] = order
            return out
        return items

    def if_statement(self, target: dict | None) -> None:
        """An if block. The language switch (game_global.is_game_text_eng) is evaluated as
        English and that branch's assignments are kept; any other condition is skipped."""
        self.next()
        cond = []
        while self.peek()[0] != "eof" and self.peek() != ("name", "then"):
            cond.append(self.next()[1])
        self.next()
        english = None
        if "is_game_text_eng" in cond:
            wants_true = "false" not in cond
            if "~=" in cond:
                wants_true = not wants_true
            english = wants_true
        take = english is True
        while True:
            stop = self.statements(target if take else None)
            if stop == "elseif":
                while self.peek()[0] != "eof" and self.peek() != ("name", "then"):
                    self.next()
                self.next()
                take = False
            elif stop == "else":
                take = english is False
            else:
                return

    def statements(self, target: dict | None) -> str:
        """Statements up to the block's elseif, else or end (returned, consumed). Assignments
        go into target, or are skipped when it is None."""
        while self.peek()[0] != "eof":
            kind, val = self.peek()
            if kind == "name" and val in ("elseif", "else", "end"):
                self.next()
                return val
            if kind == "name" and val == "if":
                self.if_statement(target)
                continue
            if kind == "name" and val in BLOCK_OPEN | {"repeat"}:
                self.skip_block()
                continue
            if kind == "name" and val == "local":
                self.next()
                continue
            if kind == "name" and self.peek(1) == ("op", "="):
                self.next()
                self.next()
                v = self.value()
                if target is not None:
                    target[val] = v
                continue
            self.next()
        return "eof"

    def chunk(self) -> dict:
        """Top-level "name = value" statements, and the English branch of language switches;
        everything else is skipped."""
        globals_: dict = {}
        while self.peek()[0] != "eof":
            kind, val = self.peek()
            if kind == "name" and val in ("function", "local"):
                if val == "local":
                    self.next()
                    continue
                self.skip_block()
                continue
            if kind == "name" and val == "if":
                self.if_statement(globals_)
                continue
            if kind == "name" and val in BLOCK_OPEN | {"repeat"}:
                self.skip_block()
                continue
            if kind == "name" and self.peek(1) == ("op", "="):
                self.next()
                self.next()
                globals_[val] = self.value()
                continue
            self.next()
        return globals_


def resolve(value, globals_: dict, depth: int = 0):
    if depth > 20:
        return None
    if isinstance(value, dict):
        if "@ref" in value:
            target = globals_.get(value["@ref"])
            if isinstance(target, (dict, list)):
                return resolve(target, globals_, depth + 1)
            return target if target is not None else value["@ref"]
        return {k: (v if k == "@order" else resolve(v, globals_, depth + 1)) for k, v in value.items()}
    if isinstance(value, list):
        return [resolve(v, globals_, depth + 1) for v in value]
    return value


def find_case_insensitive(base: pathlib.Path, rel: str) -> pathlib.Path | None:
    cur = base
    for part in pathlib.PurePosixPath(rel.replace("\\", "/")).parts:
        if part in (".", ""):
            continue
        hit = next((p for p in cur.iterdir() if p.name.lower() == part.lower()), None) if cur.is_dir() else None
        if hit is None:
            return None
        cur = hit
    return cur


def collect_images(value, out: set[str]) -> None:
    if isinstance(value, dict):
        for k, v in value.items():
            if k == "list" and isinstance(v, list):
                out.update(x for x in v if isinstance(x, str) and x)
            else:
                collect_images(v, out)
    elif isinstance(value, list):
        for v in value:
            collect_images(v, out)


def image_key(rel: str) -> str:
    """Lower-case path with a .png extension: how the copies are named."""
    p = pathlib.PurePosixPath(rel.replace("\\", "/").lstrip("./").lower())
    return str(p.with_suffix(".png"))


def rename_images(value):
    if isinstance(value, dict):
        return {k: ([image_key(x) if isinstance(x, str) and x else x for x in v] if k == "list" and isinstance(v, list) else rename_images(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [rename_images(v) for v in value]
    return value


def copy_image(src: pathlib.Path, dst: pathlib.Path) -> None:
    """PNG as is; BMP, TGA and DDS through macOS's image tool."""
    if src.suffix.lower() == ".png":
        shutil.copyfile(src, dst)
    else:
        subprocess.run(["sips", "-s", "format", "png", str(src), "--out", str(dst)], check=True, capture_output=True)


def _is_window(v: dict) -> bool:
    t = v.get("type")
    return isinstance(t, (str, dict)) and str(t.get("@ref", "") if isinstance(t, dict) else t).startswith("WINDOW_")


def main() -> None:
    data_dir = pathlib.Path(sys.argv[1]).resolve()
    out_dir = pathlib.Path(sys.argv[2]).resolve() / "ui"
    files: list[pathlib.Path] = []
    for rel in SOURCES:
        p = data_dir / rel
        # A *_kor.lua file redefines its English twin's tables with the Korean art. The menus
        # use English, so the Korean files load first and the English ones replace them.
        files += sorted(p.glob("*.lua"), key=lambda f: (not f.stem.endswith("_kor"), f.name)) if p.is_dir() else [p]
    globals_: dict = {}
    for f in files:
        globals_.update(Parser(tokenize(f.read_bytes().decode("cp949", errors="replace"))).chunk())

    # The battle HUD's dialogs, and every other window table (menus, login, rooms, shop) so the
    # recreation can rebuild the original's screens.
    windows = {name: resolve(v, globals_) for name, v in globals_.items()
               if isinstance(v, dict) and (name.startswith(ROOT_PREFIXES) or _is_window(v) or name.startswith("texture_"))}
    images: set[str] = set()
    collect_images(windows, images)
    images.update(EXTRA_IMAGES)
    copied = 0
    for rel in sorted(images):
        src = find_case_insensitive(data_dir, rel)
        if src is None:
            print(f"  missing image {rel}")
            continue
        dst = out_dir / image_key(rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        copy_image(src, dst)
        copied += 1
    # Every particle script: script/particle.lua first, then the per-effect files, which the
    # game loaded later and which replace same-named entries.
    scripts = [data_dir / "script" / "particle.lua"] + sorted((data_dir / "script" / "particle").glob("*.lua"))
    particles: dict = {}
    for src in scripts:
        if not src.exists():
            continue
        chunk = Parser(tokenize(src.read_bytes().decode("cp949", errors="replace"))).chunk()
        table = resolve(chunk.get("base_particle", {}), chunk)
        if isinstance(table, dict):
            for name, layers in table.items():
                if isinstance(layers, dict) and name != "@order":
                    particles[name] = layers
    textures = 0
    for layers in particles.values():
        for key, layer in layers.items():
            if not isinstance(layer, dict) or not isinstance(layer.get("texture"), str):
                continue
            rel = layer["texture"].replace("\\", "/").lstrip("./")
            found = find_case_insensitive(data_dir, rel)
            if found is None:
                layer["texture"] = ""
                continue
            dst = out_dir / image_key(rel)
            if not dst.exists():
                dst.parent.mkdir(parents=True, exist_ok=True)
                copy_image(found, dst)
                textures += 1
            layer["texture"] = image_key(rel)
    print(f"{len(particles)} particle scripts, {textures} new particle textures")

    # Weapon and weapon-mode tables, the body colour schemes and the sword command combos, as
    # data for the game. The combo keys are C++ enum names, so they stay strings.
    tables: dict = {}
    for name in ("weapon_parameter", "weapon_mode_parameter", "character_mapping_parameter", "combo_parameter"):
        src = data_dir / "script" / "parameter" / f"{name}.lua"
        chunk = Parser(tokenize(src.read_bytes().decode("cp949", errors="replace"))).chunk()
        tables.update({k: resolve(v, chunk) for k, v in chunk.items() if isinstance(v, (dict, list))})
    (out_dir / "parameters.json").write_text(json.dumps(tables, ensure_ascii=False, indent=1), encoding="utf-8")
    # The English game text (tooltips, system messages, character info), as data.
    text_src = data_dir / "script" / "page" / "game_text_eng.lua"
    texts = Parser(tokenize(text_src.read_bytes().decode("cp949", errors="replace"))).chunk()
    texts = {k: resolve(v, texts) for k, v in texts.items() if isinstance(v, dict)}
    (out_dir / "texts.json").write_text(json.dumps(texts, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"text tables: {sorted(texts)[:10]}")
    print(f"parameter tables: {sorted(tables)[:12]}")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "particles.json").write_text(json.dumps(particles, indent=1), encoding="utf-8")
    (out_dir / "windows.json").write_text(json.dumps(rename_images(windows), ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(files)} scripts, {len(windows)} window and texture tables, {copied} images -> {out_dir}")


if __name__ == "__main__":
    main()
