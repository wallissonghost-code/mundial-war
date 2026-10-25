"""Generate illustrative terrain colors; preserves the reference coastline."""
from pathlib import Path
import json,math
root=Path(__file__).resolve().parents[1];p=root/'data/reference-mask.json';d=json.loads(p.read_text());rows=[]
for y,row in enumerate(d['rows']):
 out=''
 for x,v in enumerate(row):
  u=x/d['width'];t=y/d['height'];wave=math.sin(x*.31)+math.cos(y*.43)+math.sin(x*.13+y*.21)
  k=0
  if v=='1':
   k=1 if wave>-.5 else 2
   if (.43<u<.64 and .35<t<.55) or (.77<u<.9 and .66<t<.8):k=3 if wave<1 else 4
   if (.25<u<.30 and .53<t<.83) or (.66<u<.77 and .27<t<.38) or (.13<u<.2 and .2<t<.4):k=4 if wave>0 else 5
   if t<.13 or t>.91:k=6
  out+=str(k)
 rows.append(out)
d['terrainRows']=rows;p.write_text(json.dumps(d,separators=(',',':')))
