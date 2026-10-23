"""Rasterize Natural Earth public-domain land into the server's embedded grid.
Source: https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_land.geojson
Projection: equirectangular, longitude -180..180, latitude 85..-65 (Antarctica excluded).
Requires Pillow. Source GeoJSON is retained in data/land.geojson.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import json,re
root=Path(__file__).resolve().parents[1]
W,H,S=240,100,4
im=Image.new("1",(W*S,H*S))
draw=ImageDraw.Draw(im)
def project(p):return ((p[0]+180)/360*W*S,(85-p[1])/150*H*S)
data=json.loads((root/"data/land.geojson").read_text())
for feature in data["features"]:
 g=feature["geometry"]
 polygons=[g["coordinates"]] if g["type"]=="Polygon" else g["coordinates"]
 for poly in polygons:
  for index,ring in enumerate(poly):
   draw.polygon([project(p) for p in ring],fill=1 if index==0 else 0)
rows=["".join("1" if im.getpixel((x*S+S//2,y*S+S//2)) else "0" for x in range(W)) for y in range(H)]
mask="local W,H = 240,100\n-- Natural Earth 110m; public domain. lon -180..180, lat 85..-65.\nlocal landRows = {\n"+",\n".join('"'+r+'"' for r in rows)+"\n}\n"
path=root/"src/server.server.lua"
text=path.read_text()
start=text.index("local W,H")
end=text.index("local cells, nations")
text=text[:start]+mask+text[end:]
text=text.replace('local land=false\n for _,p in ipairs(polygons) do if inside(x,y,p) then land=true break end end','local land=string.sub(landRows[y],x,x)=="1"')
path.write_text(text)
preview=Image.new("RGB",(W,H),(21,53,76))
for y,row in enumerate(rows):
 for x,v in enumerate(row):
  if v=="1":
   coast=any(xx<0 or xx>=W or yy<0 or yy>=H or rows[yy][xx]=="0" for xx,yy in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)])
   preview.putpixel((x,y),(180,191,142) if coast else (117,145,103))
(root/"dist").mkdir(exist_ok=True)
preview.resize((1440,600),Image.Resampling.NEAREST).save(root/"dist/map_preview.png")
print("Map:",W,H,"land:",sum(r.count("1") for r in rows))
