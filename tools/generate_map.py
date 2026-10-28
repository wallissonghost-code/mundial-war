"""Generate the Mundial War world grid from Natural Earth (public domain).

Output:
  data/world-map.json        grid + country table (used by tests and tools)
  src/shared/MapData.lua     same data as a Luau ModuleScript (run-length encoded)

Projection: Miller cylindrical, longitudes -180..180, latitudes 84N..57.8S, 2:1.
Every land cell stores the index of its country (1..N); water is 0.
"""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data" / "naturalearth"
W, H = 640, 320
SS = 4                     # supersampling factor for rasterization
LAT_TOP = 84.0
LAND_THRESHOLD = 5         # of SS*SS samples needed for a land cell
MIN_LAKE = 24              # enclosed water bodies smaller than this become land
B62 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"


def miller(lat):
    lat = max(-89.0, min(89.0, lat))
    return 1.25 * math.log(math.tan(math.pi / 4 + 0.4 * math.radians(lat)))


Y_TOP = miller(LAT_TOP)
Y_SPAN = 2 * math.pi * H / W          # keeps the 2:1 aspect of the longitude span


def project(lon, lat, scale=1):
    x = (lon + 180.0) / 360.0 * W * scale
    y = (Y_TOP - miller(lat)) / Y_SPAN * H * scale
    return x, y


def polygons(geometry):
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    return []


SHORT_NAMES = {
    "COD": "RD Congo", "COG": "Congo", "CAF": "Rep. Centro-Africana", "USA": "EUA",
    "ARE": "Emirados Árabes", "BIH": "Bósnia", "DOM": "Rep. Dominicana", "PNG": "Papua-Nova Guiné",
    "TTO": "Trinidad e Tobago", "KNA": "São Cristóvão", "VCT": "São Vicente", "STP": "São Tomé",
    "SSD": "Sudão do Sul", "GNQ": "Guiné Equatorial", "ATF": "Terras Austrais Fr.", "SGS": "Geórgia do Sul",
    "FLK": "Malvinas", "HMD": "Ilhas Heard", "TCA": "Turks e Caicos", "VIR": "Ilhas Virgens",
    "VGB": "Ilhas Virgens Br.", "CZE": "Tchéquia", "MKD": "Macedônia do Norte", "PRK": "Coreia do Norte",
    "KOR": "Coreia do Sul", "IRL": "Irlanda",
}


def short_name(code, name):
    if code in SHORT_NAMES:
        return SHORT_NAMES[code]
    return name if len(name) <= 20 else name[:19].rstrip() + "."


def b62(n, width):
    out = ""
    for _ in range(width):
        out = B62[n % 62] + out
        n //= 62
    assert n == 0
    return out


def main():
    countries = json.loads((SRC / "ne_50m_admin_0_countries.geojson").read_text())["features"]
    places = json.loads((SRC / "ne_50m_populated_places_simple.geojson").read_text())["features"]
    countries = [c for c in countries if c["properties"]["CONTINENT"] != "Antarctica"]
    countries.sort(key=lambda c: c["properties"]["ADM0_A3"])

    big = Image.new("I", (W * SS, H * SS), 0)
    draw = ImageDraw.Draw(big)
    for index, feature in enumerate(countries, start=1):
        for poly in polygons(feature["geometry"]):
            outer = [project(lon, lat, SS) for lon, lat in poly[0]]
            if len(outer) >= 3:
                draw.polygon(outer, fill=index)
            for hole in poly[1:]:
                pts = [project(lon, lat, SS) for lon, lat in hole]
                if len(pts) >= 3:
                    draw.polygon(pts, fill=0)
    fine = np.array(big, dtype=np.int32).reshape(H, SS, W, SS).transpose(0, 2, 1, 3).reshape(H, W, SS * SS)

    land_samples = (fine > 0).sum(axis=2)
    grid = np.zeros((H, W), dtype=np.int32)
    best = np.zeros((H, W), dtype=np.int32)
    for index in range(1, len(countries) + 1):
        count = (fine == index).sum(axis=2)
        better = count > best
        grid[better] = index
        best[better] = count[better]
    grid[land_samples < LAND_THRESHOLD] = 0

    # Small countries/islands that vanished: stamp one cell at their largest polygon's centroid.
    present = set(np.unique(grid).tolist())
    for index, feature in enumerate(countries, start=1):
        if index in present:
            continue
        largest = max(polygons(feature["geometry"]), key=lambda p: len(p[0]), default=None)
        if not largest:
            continue
        xs, ys = zip(*[project(lon, lat) for lon, lat in largest[0]])
        x, y = int(min(W - 1, max(0, sum(xs) / len(xs)))), int(min(H - 1, max(0, sum(ys) / len(ys))))
        if grid[y, x] == 0:
            grid[y, x] = index

    # Fill tiny enclosed lakes so the coast stays clean (oceans and big lakes stay water).
    water = grid == 0
    label = np.zeros((H, W), dtype=np.int32)
    comps = []
    for sy in range(H):
        for sx in range(W):
            if water[sy, sx] and not label[sy, sx]:
                cid = len(comps) + 1
                stack, cells = [(sy, sx)], []
                label[sy, sx] = cid
                while stack:
                    y, x = stack.pop()
                    cells.append((y, x))
                    for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                        if 0 <= ny < H and 0 <= nx < W and water[ny, nx] and not label[ny, nx]:
                            label[ny, nx] = cid
                            stack.append((ny, nx))
                comps.append(cells)
    for cells in comps:
        if len(cells) < MIN_LAKE:
            for y, x in cells:
                votes = {}
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < H and 0 <= nx < W and grid[ny, nx] > 0:
                        votes[grid[ny, nx]] = votes.get(grid[ny, nx], 0) + 1
                if votes:
                    grid[y, x] = max(votes, key=votes.get)

    # Capitals: Natural Earth "Admin-0 capital" places, snapped to the nearest cell of that country.
    capitals = {}
    for place in places:
        p = place["properties"]
        if p.get("adm0cap") == 1 or p.get("featurecla", "").startswith("Admin-0 capital"):
            key = p.get("adm0_a3")
            pop = p.get("pop_max") or 0
            if key and (key not in capitals or pop > capitals[key][2]):
                lon, lat = place["geometry"]["coordinates"]
                capitals[key] = (lon, lat, pop)

    table = []
    for index, feature in enumerate(countries, start=1):
        p = feature["properties"]
        ys, xs = np.nonzero(grid == index)
        if len(xs) == 0:
            continue
        code = p["ADM0_A3"]
        if code in capitals:
            cx, cy = project(capitals[code][0], capitals[code][1])
        else:
            cx, cy = xs.mean(), ys.mean()
        k = int(np.argmin((xs + 0.5 - cx) ** 2 + (ys + 0.5 - cy) ** 2))
        table.append({
            "index": index,
            "code": code,
            "name": short_name(p["ADM0_A3"], p.get("NAME_PT") or p["NAME"]),
            "continent": p["CONTINENT"],
            "population": int(p.get("POP_EST") or 0),
            "cells": int(len(xs)),
            "capital": int(ys[k]) * W + int(xs[k]) + 1,
        })

    # Re-index compactly so ids are 1..N in table order.
    remap = {row["index"]: n for n, row in enumerate(table, start=1)}
    compact = np.zeros_like(grid)
    for old, new in remap.items():
        compact[grid == old] = new
    for n, row in enumerate(table, start=1):
        row["index"] = n

    rows = []
    for y in range(H):
        line, x = [], 0
        while x < W:
            v = int(compact[y, x])
            stop = x + 1
            while stop < W and compact[y, stop] == v:
                stop += 1
            line.append(b62(v, 2) + b62(stop - x, 2))
            x = stop
        rows.append("".join(line))

    land = int((compact > 0).sum())
    data = {"width": W, "height": H, "projection": "Miller 84N..57.8S",
            "source": "Natural Earth 1:50m admin-0 countries and populated places (public domain)",
            "land": land, "rows": rows, "countries": table}
    (ROOT / "data" / "world-map.json").write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False))

    lua = ["-- GENERATED by tools/generate_map.py from Natural Earth (public domain). Do not edit by hand.",
           "-- rows: run-length encoded; each run = 2 base62 chars country index (0 = water) + 2 base62 chars length.",
           "return {",
           f"\tW = {W},", f"\tH = {H},", f"\tLand = {land},",
           '\tAlphabet = "' + B62 + '",',
           "\tRows = {"]
    lua += ['\t\t"' + r + '",' for r in rows]
    lua.append("\t},")
    lua.append("\tCountries = {")
    for row in table:
        lua.append('\t\t{code = %s, name = %s, continent = %s, cells = %d, capital = %d, population = %d},' % (
            json.dumps(row["code"]), json.dumps(row["name"], ensure_ascii=False), json.dumps(row["continent"]),
            row["cells"], row["capital"], row["population"]))
    lua.append("\t},")
    lua.append("}")
    out = ROOT / "src" / "shared" / "MapData.lua"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lua) + "\n", encoding="utf-8")
    print(f"map {W}x{H}: land {land} cells, {len(table)} countries, {sum(len(r) for r in rows)} bytes of rows")
    return compact, table


if __name__ == "__main__":
    main()
