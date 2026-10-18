# A small hatchback under a fitted cover, three-quarter view, on the app's 1200x640 car canvas.
# Drawn at 4x and shrunk: body silhouette, soft top light, fabric folds, wheels pressing through.
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S=4; W,H=1200*S,640*S
def P(pts): return [(x*S,y*S) for x,y in pts]
def bez(p0,p1,p2,p3,n=40):
    t=np.linspace(0,1,n)[:,None]; p0,p1,p2,p3=map(np.array,(p0,p1,p2,p3))
    return [tuple(v) for v in ((1-t)**3*p0+3*(1-t)**2*t*p1+3*(1-t)*t**2*p2+t**3*p3)]
# Outline, clockwise from the rear bottom (left = rear, right = front, car faces right like the 500e).
o=[]
o+=bez((304,452),(298,400),(302,350),(316,318))          # tailgate
o+=bez((316,318),(336,262),(382,214),(452,192))          # rear window, sloping
o+=bez((452,192),(540,172),(670,170),(742,192))          # roof
o+=bez((742,192),(786,210),(826,256),(862,288))          # windscreen
o+=bez((862,288),(916,298),(968,318),(988,348))          # bonnet
o+=bez((988,348),(1004,382),(1004,428),(992,458))        # nose
# Hem: lifts over each wheel, hangs lower between them.
o+=bez((992,458),(960,470),(930,452),(902,446))
o+=bez((902,446),(870,440),(820,440),(796,452))
o+=bez((796,452),(760,472),(520,474),(470,452))
o+=bez((470,452),(446,440),(392,440),(364,448))
o+=bez((364,448),(338,456),(318,462),(304,452))
body=Image.new('L',(W,H),0); ImageDraw.Draw(body).polygon(P(o),fill=255)
body=body.filter(ImageFilter.GaussianBlur(1.2*S))
m=np.asarray(body).astype(float)/255
# Shading: light from above; darker toward the hem; zinc tones.
y=np.linspace(0,1,H)[:,None]*np.ones((1,W))
top,bot=np.array([132,132,140]),np.array([40,40,46])
shade=(np.clip((y*640-170)/320,0,1))[...,None]
col=top*(1-shade)+bot*shade
def soft(pts,width,blur,val):
    L=Image.new('L',(W,H),0); ImageDraw.Draw(L).line(P(pts),fill=val,width=int(width*S),joint='curve')
    return np.asarray(L.filter(ImageFilter.GaussianBlur(blur*S))).astype(float)/255
# Highlight along the roof and the bonnet's top edge.
hi=soft(bez((420,205),(520,182),(660,180),(735,206)),18,14,255)*0.55+soft(bez((870,300),(920,306),(955,320),(972,340)),10,10,255)*0.35
# Folds: a soft dark crease down the side, one off the windscreen, one at the rear.
fold=soft(bez((600,215),(590,300),(585,380),(595,480)),16,16,255)*0.30 \
    +soft(bez((780,240),(760,320),(750,400),(760,485)),12,14,255)*0.26 \
    +soft(bez((360,300),(370,360),(385,420),(400,482)),12,14,255)*0.22 \
    +soft(bez((520,330),(640,350),(820,360),(940,380)),10,18,255)*0.16
# Wheels pressing through: a lighter ring top, darker inside, near the hem.
def wheel(cx,cy,r):
    ring=Image.new('L',(W,H),0); d=ImageDraw.Draw(ring)
    d.arc([(cx-r)*S,(cy-r)*S,(cx+r)*S,(cy+r)*S],200,340,fill=255,width=int(9*S))
    inner=Image.new('L',(W,H),0); ImageDraw.Draw(inner).ellipse([(cx-r*.82)*S,(cy-r*.82)*S,(cx+r*.82)*S,(cy+r*.82)*S],fill=255)
    return (np.asarray(ring.filter(ImageFilter.GaussianBlur(5*S))).astype(float)/255,
            np.asarray(inner.filter(ImageFilter.GaussianBlur(10*S))).astype(float)/255)
r1,i1=wheel(416,462,60); r2,i2=wheel(849,466,64)
c=col.copy()
c=c+(255-c)*hi[...,None]*0.5
c=c*(1-fold[...,None])
c=c+(255-c)*((r1+r2)*0.18)[...,None]
c=c*(1-((i1+i2)*0.22)[...,None])
# Hem: a darker band where the cloth gathers at the ground.
hem=soft(bez((470,456),(560,470),(720,470),(796,456)),8,6,255)*0.40
c=c*(1-hem[...,None])
tyres=Image.new('RGBA',(W,H),(0,0,0,0)); td=ImageDraw.Draw(tyres)
for cx,cy,w in ((416,470,104),(849,474,110)):
    td.rounded_rectangle([(cx-w/2)*S,(cy-30)*S,(cx+w/2)*S,(cy+18)*S],radius=16*S,fill=(16,16,18,255))
    td.rounded_rectangle([(cx-w/2+8)*S,(cy+2)*S,(cx+w/2-8)*S,(cy+10)*S],radius=4*S,fill=(36,36,40,255))
tyres=tyres.filter(ImageFilter.GaussianBlur(0.8*S))
img=np.dstack([np.clip(c,0,255),m*255]).astype(np.uint8)
cover=Image.fromarray(img)
tyres.alpha_composite(cover)
img=np.asarray(tyres)
out=Image.fromarray(img).resize((1200,640),Image.LANCZOS)
out.save('car-covered.png')
bg=Image.new('RGBA',(1200,640),(14,14,16,255)); bg.alpha_composite(out); bg.convert('RGB').save('preview.png')
print('ok')
