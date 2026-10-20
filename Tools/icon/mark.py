from PIL import Image, ImageDraw, ImageFilter
import numpy as np, sys

def bez(p0,p1,p2,p3,n=400):
    t=np.linspace(0,1,n)[:,None]
    return (1-t)**3*p0+3*(1-t)**2*t*p1+3*(1-t)*t**2*p2+t**3*p3

P=lambda x,y: np.array([x,y],float)
# One wave-V: a small lift at each end, a steep fall, a soft round bottom. Symmetric.
segs=[(P(232,418),P(292,384),P(346,410),P(392,474)),
      (P(392,474),P(442,546),P(468,624),P(512,624))]
def mirror(s): return tuple(P(1024-p[0],p[1]) for p in s[::-1])
path=np.vstack([bez(*s) for s in segs]+[bez(*mirror(s)) for s in segs[::-1]])
path[:,1]+= 512-(path[:,1].min()+path[:,1].max())/2   # centre vertically

def draw(size, stroke, bg=(9,9,11), glow=0.0, scale_mark=1.0):
    S=4; W=size*S
    img=Image.new('RGB',(W,W),bg)
    # a barely-there lift at the top, so the dark reads as a surface, not a hole
    grad=np.linspace(1,0,W)[:,None]*np.ones((1,W))
    top=np.array([24,24,28]); base=np.array(bg)
    arr=(base+(top-base)*grad[...,None]**2).astype(np.uint8)
    img=Image.fromarray(arr,'RGB')
    pts=(path-512)*scale_mark+512
    pts=pts*W/1024; r=stroke*W/1024/2
    if glow>0:
        g=Image.new('L',(W,W),0); gd=ImageDraw.Draw(g)
        for x,y in pts[::3]: gd.ellipse((x-r*2.2,y-r*2.2,x+r*2.2,y+r*2.2),fill=255)
        g=g.filter(ImageFilter.GaussianBlur(W*0.05))
        orange=Image.new('RGB',(W,W),(251,146,60))
        img=Image.composite(orange,img,g.point(lambda v:int(v*glow)))
    m=Image.new('L',(W,W),0); md=ImageDraw.Draw(m)
    for x,y in pts: md.ellipse((x-r,y-r,x+r,y+r),fill=255)
    img=Image.composite(Image.new('RGB',(W,W),(251,146,60)),img,m)
    return img.resize((size,size),Image.LANCZOS)

if __name__=='__main__':
    draw(1024,50).save('icon-a.png')
    draw(1024,50,glow=0.16).save('icon-b.png')
    draw(1024,64,scale_mark=0.92).save('icon-c.png')
