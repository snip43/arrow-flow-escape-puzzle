"""Audit the published JSON independently and export one metrics row per level."""
import csv
import json
from collections import Counter
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = [(1, 0), (0, 1), (-1, 0), (0, -1)]


def audit(level):
    paths = {a["id"]: list(map(tuple, a["path"])) for a in level["arrows"]}
    width, height = level["width"], level["height"]
    occupied = {p: key for key, path in paths.items() for p in path}
    lengths = Counter(map(len, paths.values()))
    n = len(paths)
    cells = sum(length * count for length, count in lengths.items())
    assert len(occupied) == cells
    turns, directions, blockers = [], [0] * 4, {}
    for key, path in paths.items():
        steps = [(b[0]-a[0], b[1]-a[1]) for a, b in zip(path, path[1:])]
        assert all(s in DIRECTIONS for s in steps)
        turns.append(sum(a != b for a, b in zip(steps, steps[1:])))
        dx, dy = steps[-1]
        directions[DIRECTIONS.index((dx, dy))] += 1
        x, y = path[-1]
        ray = set()
        while True:
            x, y = x + dx, y + dy
            if not (0 <= x < width and 0 <= y < height):
                break
            if (x, y) in occupied:
                ray.add(occupied[x, y])
        blockers[key] = ray

    edges = sum(map(len, blockers.values()))
    free = sum(not deps for deps in blockers.values()) / n
    depths = {}
    # In a solution, every predecessor already has its final depth.
    for key in level["solution"]:
        depths[key] = 1 + max((depths[b] for b in blockers[key]), default=0)
    assert len(depths) == n
    chain = max(depths.values())
    coverage = cells / (width * height)
    computed = dict(arrows=n, cells=cells, coverage=coverage, directions=directions,
                    bent=sum(t > 0 for t in turns)/n, multi=sum(t >= 2 for t in turns),
                    lengths={str(k): v for k, v in lengths.items()}, free=free,
                    edges=edges, chain=chain, waves=chain, deadlocks=0,
                    difficulty=(coverage+n/32+1-free+chain/16+edges/(3*n))/5)
    # Stable Kahn waves. Count states with exactly one legal move.
    remaining = set(paths)
    ready = sorted(k for k in remaining if not blockers[k])
    forced = 0
    while ready:
        following = []
        for key in ready:
            forced += sum(not (blockers[k] & remaining) for k in remaining) == 1
            remaining.remove(key)
            following.extend(sorted(k for k in remaining if key in blockers[k]
                                    and not (blockers[k] & remaining)))
        ready = following
    assert not remaining
    computed.update(forced=forced, choice=n-forced)
    for field, value in computed.items():
        stored = level["metrics"][field]
        assert (abs(stored-value) < 1e-12 if isinstance(value, float) else value == stored), (level["level_id"], field)
    return {**{k: level[k] for k in ("level_id","seed","tier","width","height")}, **computed}


def main():
    levels = json.loads((ROOT/"levels/data/catalog.json").read_bytes())
    rows = [audit(level) for level in levels]
    with (ROOT/"docs/stage_1c_metrics.csv").open("w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: json.dumps(v, sort_keys=True) if isinstance(v, (list,dict)) else v
                             for k, v in row.items()})
    for tier in ("Tutorial","Easy","Normal","Hard"):
        group = [r for r in rows if r["tier"] == tier]
        values = []
        for key in ("coverage","arrows","bent","free","chain","difficulty"):
            samples = [r[key]*(100 if key in ("coverage","bent","free") else 1) for r in group]
            values.append(" / ".join(f"{x:.2f}" for x in (min(samples),median(samples),max(samples))))
        print(tier, len(group), *values, sep=" | ")


if __name__ == "__main__":
    main()
