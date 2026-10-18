"""
Exports the game-data tables from the original SQL Server 2000 backup to JSON, without
restoring it. Reads 8 KB data pages straight out of the backup file, takes column layouts
from the backup's own syscolumns, and finds rows by their record headers rather than the
page slot arrays (at least one page has a stale slot table).

Only balance and catalogue tables are exported. Player, clan, log and billing tables are
skipped on purpose: they hold real players' data.

    python3 -I godot/tools/extract_db.py <raycrash1 backup> <output dir>
"""

from __future__ import annotations

import json
import pathlib
import struct
import sys

PAGE = 8192

GAME_TABLES = {
    "RobotInfo", "WeaponInfo", "ArmorInfo", "ArmorPartInfo", "ArmorPartType", "MCSInfo",
    "SensorInfo", "BitInfo", "ColorInfo", "GradeInfo", "FMInfo", "FMUpgradeChart",
    "waste_item", "Shop_List", "MaxUseInfo", "Raycrash_Map_Index",
}

# Columns whose syscolumns rows could not be read. Name from the server's own SELECT
# (get_weapon_info_db lists continuous_time, the only WeaponInfo column otherwise missing).
KNOWN_GAPS = {"WeaponInfo": {14: ("continuous_time", 0x38)}}

# SQL Server 2000 type ids -> (struct format or None for variable/char, byte length)
FIXED_TYPES = {
    0x30: ("<B", 1),  # tinyint
    0x34: ("<h", 2),  # smallint
    0x38: ("<i", 4),  # int
    0x7F: ("<q", 8),  # bigint
    0x3B: ("<f", 4),  # real
    0x3E: ("<d", 8),  # float
    0x3A: ("<I", 4),  # smalldatetime (raw)
    0x3D: ("<Q", 8),  # datetime (raw)
    0x7A: ("<i", 4),  # smallmoney (x 10000)
    0x3C: ("<q", 8),  # money (x 10000)
}
CHAR_TYPES = {0xAF: "cp949", 0xA7: "cp949", 0xEF: "utf-16-le", 0xE7: "utf-16-le"}
BIT = 0x68


class Backup:
    def __init__(self, path: pathlib.Path) -> None:
        self.data = path.read_bytes()
        self.base = self._find_alignment()

    def _find_alignment(self) -> int:
        best = (0, -1)
        for base in range(0, PAGE, 512):
            ok = sum(
                1
                for off in range(base, min(len(self.data), base + PAGE * 400), PAGE)
                if self.data[off] == 1 and self.data[off + 1] in (1, 2, 3, 10, 11)
            )
            if ok > best[1]:
                best = (base, ok)
        return best[0]

    def pages(self, obj_id: int):
        for off in range(self.base, len(self.data) - PAGE + 1, PAGE):
            d = self.data
            if d[off] == 1 and d[off + 1] == 1 and struct.unpack_from("<i", d, off + 24)[0] == obj_id:
                yield off

    def slot_rows(self, off: int):
        n = struct.unpack_from("<H", self.data, off + 22)[0]
        for s in range(n):
            r = struct.unpack_from("<H", self.data, off + PAGE - 2 * (s + 1))[0]
            if 96 <= r < PAGE:
                yield off + r

    def table_rows(self, obj_id: int):
        """All primary records of a table, found by header scan using the table's usual shape."""
        from collections import Counter
        offs = list(self.pages(obj_id))
        shapes = Counter()
        for off in offs:
            for p in self.slot_rows(off):
                fe = struct.unpack_from("<H", self.data, p + 2)[0]
                if 4 <= fe < PAGE - 96 and p + fe + 2 <= off + PAGE:
                    shapes[(fe, struct.unpack_from("<H", self.data, p + fe)[0])] += 1
        if not shapes:
            return []
        fe, ncols = shapes.most_common(1)[0][0]
        found = []
        for off in offs:
            found.extend(self.scan_rows(off, fe, ncols))
        return found

    def scan_rows(self, off: int, fixed_end: int, ncols: int):
        """Every primary record on the page whose header matches the table's layout. The second
        status byte may carry bit 0, which WeaponInfo's Saber Type 1 row (id 21) has."""
        d = self.data
        free = struct.unpack_from("<H", d, off + 30)[0] or PAGE
        p = off + 96
        end = off + min(free, PAGE - 2)
        while p < end - 4:
            a, b = d[p], d[p + 1]
            if (a & 0x0E) == 0 and (a & 0x10) and b in (0, 1) and struct.unpack_from("<H", d, p + 2)[0] == fixed_end:
                if p + fixed_end + 2 <= end and struct.unpack_from("<H", d, p + fixed_end)[0] == ncols:
                    yield p
            p += 1

    def record(self, p: int):
        d = self.data
        status = d[p]
        fixed_end = struct.unpack_from("<H", d, p + 2)[0]
        ncols = struct.unpack_from("<H", d, p + fixed_end)[0]
        nb = (ncols + 7) // 8
        nulls = d[p + fixed_end + 2 : p + fixed_end + 2 + nb]
        q = p + fixed_end + 2 + nb
        var = []
        if status & 0x20:
            nvar = struct.unpack_from("<H", d, q)[0]
            start = q + 2 + 2 * nvar
            for i in range(nvar):
                e = struct.unpack_from("<H", d, q + 2 + 2 * i)[0] & 0x7FFF
                var.append(d[start : p + e])
                start = p + e
        return fixed_end, ncols, nulls, var


def table_ids(db: Backup) -> dict[str, int]:
    out = {}
    for p in db.table_rows(1):  # sysobjects
        if True:
            try:
                fe, n, nulls, var = db.record(p)
            except Exception:
                continue
            if not var:
                continue
            fixed = db.data[p + 4 : p + fe]
            if fixed[4:6].decode("ascii", "replace").strip() == "U":
                out[var[0].decode("utf-16-le", "replace")] = struct.unpack_from("<i", fixed, 0)[0]
    return out


def columns(db: Backup, obj_id: int) -> list[dict]:
    cols = []
    for p in db.table_rows(3):  # syscolumns
        if True:
            try:
                fe, n, nulls, var = db.record(p)
            except Exception:
                continue
            fixed = db.data[p + 4 : p + fe]
            if len(fixed) < 18 or not var or struct.unpack_from("<i", fixed, 0)[0] != obj_id:
                continue
            cols.append({
                "name": var[0].decode("utf-16-le", "replace"),
                "xtype": fixed[4],
                "length": struct.unpack_from("<h", fixed, 8)[0],
                "colid": struct.unpack_from("<h", fixed, 12)[0],
                "xoffset": struct.unpack_from("<h", fixed, 14)[0],
                "bitpos": fixed[16],
            })
    # Backups can carry stale copies of system rows. Keep the most common definition per column.
    from collections import Counter, defaultdict
    by_id = defaultdict(Counter)
    for c in cols:
        by_id[c["colid"]][tuple(sorted(c.items()))] += 1
    best = [dict(counter.most_common(1)[0][0]) for counter in by_id.values()]
    best.sort(key=lambda c: c["colid"])
    return best


def decode(db: Backup, p: int, cols: list[dict]) -> dict:
    fe, ncols, nulls, var = db.record(p)
    row = {}
    for c in cols:
        i = c["colid"] - 1
        is_null = bool(nulls[i // 8] & (1 << (i % 8))) if i // 8 < len(nulls) else False
        if is_null:
            row[c["name"]] = None
            continue
        x, off = c["xtype"], c["xoffset"]
        if x == BIT:
            row[c["name"]] = bool(db.data[p + off] & (1 << c["bitpos"]))
        elif x in FIXED_TYPES:
            fmt, _ = FIXED_TYPES[x]
            row[c["name"]] = struct.unpack_from(fmt, db.data, p + off)[0]
        elif x in CHAR_TYPES:
            if off > 0:
                raw = db.data[p + off : p + off + c["length"]]
            else:
                idx = -off - 1
                raw = var[idx] if idx < len(var) else b""
            row[c["name"]] = raw.decode(CHAR_TYPES[x], "replace").rstrip(" \x00")
        else:
            row[c["name"]] = None
    return row


def fixed_length(cols: list[dict]) -> int:
    end = 4
    for c in cols:
        if c["xoffset"] > 0:
            size = FIXED_TYPES.get(c["xtype"], (None, c["length"]))[1] if c["xtype"] != BIT else 1
            end = max(end, c["xoffset"] + size)
    return end


def main() -> None:
    db = Backup(pathlib.Path(sys.argv[1]))
    out_dir = pathlib.Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    ids = table_ids(db)
    for name in sorted(GAME_TABLES):
        if name not in ids:
            print(f"{name}: not in backup")
            continue
        cols = columns(db, ids[name])
        colids = [c["colid"] for c in cols]
        gaps = sorted(set(range(1, max(colids) + 1)) - set(colids)) if colids else []
        rows = []
        for p in db.table_rows(ids[name]):
            try:
                rows.append(decode(db, p, cols))
            except Exception as e:  # skip a damaged record rather than stop
                print(f"  {name}: skipped a record ({e})")
        for colid, (gname, gtype) in KNOWN_GAPS.get(name, {}).items():
            if colid in gaps:
                prev = max((c for c in cols if c["colid"] < colid and c["xoffset"] > 0), key=lambda c: c["xoffset"])
                off = prev["xoffset"] + FIXED_TYPES.get(prev["xtype"], (None, prev["length"]))[1]
                cols.append({"name": gname, "xtype": gtype, "length": 4, "colid": colid, "xoffset": off, "bitpos": 0})
                cols.sort(key=lambda c: c["colid"])
                gaps.remove(colid)
                rows = [decode(db, p, cols) for p in db.table_rows(ids[name])]
                print(f"  {name}: column {colid} read as {gname} at offset {off} (named from the server query)")
        if gaps:
            print(f"  {name}: column ids {gaps} not found in syscolumns (dropped or unreadable)")
        # Same for data rows: keep one row per key, the most common version of it.
        if cols:
            from collections import Counter, defaultdict
            key0 = cols[0]["name"]
            versions = defaultdict(Counter)
            for r in rows:
                versions[r.get(key0)][json.dumps(r, sort_keys=True, ensure_ascii=False)] += 1
            conflicts = sum(1 for v in versions.values() if len(v) > 1)
            rows = [json.loads(v.most_common(1)[0][0]) for v in versions.values()]
            if conflicts:
                print(f"  {name}: {conflicts} keys had differing copies, kept the most common")
        key = cols[0]["name"] if cols else None
        if key:
            rows.sort(key=lambda r: (r.get(key) is None, r.get(key)))
        (out_dir / f"{name}.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"{name}: {len(rows)} rows, {len(cols)} columns")


if __name__ == "__main__":
    main()
