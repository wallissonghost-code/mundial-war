"""Embed the gameplay silhouette derived from the user's reference image.
The source grid in data/reference-mask.json preserves the illustration's layout;
it is not a geographic projection and must not be indexed by longitude/latitude.
"""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
data=json.loads((root/"data/reference-mask.json").read_text())
W,H=data["width"],data["height"]
rows=data["rows"]
assert len(rows)==H and all(len(r)==W and set(r)<=set("01") for r in rows)
mask=f"local W,H = {W},{H}\n-- Silhouette traced from user reference; illustrative coordinates.\nlocal landRows = {{\n"+",\n".join('"'+r+'"' for r in rows)+"\n}\n"
path=root/"src/server.server.lua"
text=path.read_text()
start=text.index("local W,H")
end=text.index("local cells, nations")
path.write_text(text[:start]+mask+text[end:])
print("Map:",W,H,"land:",sum(r.count("1") for r in rows))
