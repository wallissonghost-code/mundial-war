from PIL import Image
from scipy import ndimage as nd
import numpy as np,json
from pathlib import Path
import argparse
parser=argparse.ArgumentParser()
parser.add_argument('image',help='Original user reference image')
args=parser.parse_args()
im=np.array(Image.open(args.image).convert('RGB')).astype(np.int16)
bright=(im.max(2)-im.min(2)<44)&(im.mean(2)>105)
water=(im[:,:,2]-im[:,:,0]>18)&(im[:,:,1]-im[:,:,0]>7)
# Borders are dark ink, not channels of water. Recover ink within 4 source pixels of land.
land=bright | (nd.binary_dilation(bright,iterations=4)&~water)
W,H=320,180
small=np.array(Image.fromarray((land*255).astype('uint8')).resize((W,H),Image.Resampling.BOX))>=112
# Region cores come from actual light interiors separated by the reference ink.
cores=(im.mean(2)>150)&(im.max(2)-im.min(2)<38)
cores=nd.binary_opening(cores,iterations=1)
labels,n=nd.label(cores)
sizes=np.bincount(labels.ravel()); valid=sizes>=90;valid[0]=False
labels=np.where(valid[labels],labels,0)
_,idx=nd.distance_transform_edt(labels==0,return_indices=True)
filled=labels[tuple(idx)]
yy=np.minimum((np.arange(H)+.5)*im.shape[0]/H,im.shape[0]-1).astype(int)
xx=np.minimum((np.arange(W)+.5)*im.shape[1]/W,im.shape[1]-1).astype(int)
reg=filled[np.ix_(yy,xx)];reg[~small]=0
unique=[v for v in np.unique(reg) if v];mapping={v:i+1 for i,v in enumerate(unique)}
reg=np.array([mapping.get(v,0) for v in reg.ravel()]).reshape(H,W)
data={"width":W,"height":H,"source":"User reference: repaired ink borders; traced region interiors.","rows":["".join(map(str,r.astype(int))) for r in small],"regionRows":["".join(f"{v:03x}" for v in row) for row in reg]}
(Path(__file__).resolve().parents[1]/'data/reference-mask.json').write_text(json.dumps(data,separators=(',',':')))
print("Land",int(small.sum()),"Regions",len(unique))
