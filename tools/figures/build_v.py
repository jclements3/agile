# build_v.py -- draws docs/img/mbse-devsecops-agile-v.svg: the systems V (needs .. operations) with the MBSE model and
# its digital thread, agile increments, the DevSecOps loop under BUILD, and the digital twin feeding back to needs.
# Needs Python 3 and the Tabler icons (MIT licence, https://tabler.io/icons; e.g. `npm install @tabler/icons`):
#   TABLER_ICONS=path/to/@tabler/icons/icons/outline/ python3 tools/figures/build_v.py [OUT.svg]
# Default OUT: mbse-devsecops-agile.svg in the current directory; the committed copy is docs/img/mbse-devsecops-agile-v.svg.
# Not part of the core-Perl kit: the SVG is committed, so nothing needs this script unless the figure changes.
import math, os, re, sys
ICON=os.path.join(os.environ.get("TABLER_ICONS", "node_modules/@tabler/icons/icons/outline"), "")
def icon(name, x, y, size, color, sw=2):
    s=open(ICON+name+".svg").read()
    paths="".join(re.findall(r"<(?:path|circle|rect|line|polyline|ellipse)(?![^>]*stroke=\"none\")[^>]*/>",s))
    k=size/24
    return (f'<g transform="translate({x-size/2:.1f},{y-size/2:.1f}) scale({k:.3f})" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{paths}</g>')

W,H=1600,800
C=dict(ink="#1F2A37", blue="#2F5D8A", bluebg="#DCE8F5", bluedk="#1B3A5C",
       green="#1F7A5A", greenbg="#DDF1E8", greendk="#0F4A36",
       purple="#6B4FD8", purplebg="#EEEBFD", purpledk="#3C2A8F",
       coral="#E08A6D", coraldk="#B5583A", gold="#D4A017", goldbg="#FDF3D6",
       cyan="#22B8CF", gray="#9A9A94", buildbg="#ECEAE4", builddk="#6B6A64")
FONT="Inter, 'Helvetica Neue', Arial, sans-serif"
out=[]
A=out.append
A(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" '
  f'aria-label="MBSE, DevSecOps, agile and digital twin integrated with the systems V">')
A('<title>MBSE, agile, DevSecOps and digital twin on the systems V</title>')
A(f'''<defs>
<marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="{C['gray']}"/></marker>
<marker id="ahc" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path d="M0 0L10 5L0 10z" fill="{C['cyan']}"/></marker>
<filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="5"/></filter>
</defs>''')
A(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

# ---------- stage blocks (3D slabs)
def slab(x,y,w,h,label,face,edge,text,depth=12):
    A(f'<path d="M{x},{y+h} L{x-depth},{y+h+depth} L{x+w-depth},{y+h+depth} L{x+w},{y+h} Z" fill="{edge}"/>')
    A(f'<path d="M{x},{y} L{x-depth},{y+depth} L{x-depth},{y+h+depth} L{x},{y+h} Z" fill="{edge}" opacity="0.85"/>')
    A(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" fill="{face}" stroke="{edge}" stroke-width="2"/>')
    A(f'<text x="{x+w/2}" y="{y+h/2+9}" text-anchor="middle" font-family="{FONT}" font-weight="800" '
      f'font-size="26" letter-spacing="0.5" fill="{text}">{label}</text>')
BW,BH=270,78
L=[("NEEDS",130,300),("REQUIREMENTS",235,420),("ARCHITECTURE",340,540)]
R=[("OPERATIONS",1200,300),("VERIFICATION",1095,420),("INTEGRATION",990,540)]

# Track lying flat on the ground, seen in perspective; BUILD's point aims at its centre.
cx,cy=800,520           # screen position of the track centre
a=640                   # lemniscate half-length on the ground
K=0.40                  # ground-to-screen depth factor (lower = flatter)
D=900                   # viewer distance for perspective (lower = stronger)
BAND=74                 # band width on the ground
def proj(X,Z):          # ground (X right, Z away from viewer) -> screen
    s=D/(D+Z*K*2)
    return cx + X*s, cy - Z*K*s, s
def lem(t):             # Bernoulli lemniscate on the ground
    d=1+math.sin(t)**2
    return a*math.cos(t)/d, a*math.sin(t)*math.cos(t)/d*1.15
N=240
ts=[2*math.pi*i/N for i in range(N+1)]
cen=[lem(t) for t in ts]
def edges(off):
    out=[]
    for i,(X,Z) in enumerate(cen):
        X2,Z2=cen[(i+1)%N]; X0,Z0=cen[i-1]
        tx,tz=X2-X0,Z2-Z0; L=math.hypot(tx,tz) or 1
        nx,nz=-tz/L,tx/L
        out.append(proj(X+nx*off, Z+nz*off))
    return out
outer, inner = edges(BAND/2), edges(-BAND/2)
def strip(dy, fill, stroke=None):
    # draw quad by quad so the strand crossing at the centre overlaps naturally
    order=list(range(N))
    for i in order:
        p=[outer[i],outer[i+1],inner[i+1],inner[i]]
        d="M"+" L".join(f"{x:.1f},{y+dy:.1f}" for x,y,_ in p)+" Z"
        A(f'<path d="{d}" fill="{fill}" stroke="{stroke or fill}" stroke-width="0.8"/>')
strip(14, C["coraldk"])                       # side of the slab (near edge thickness)
strip(0, C["coral"])                          # top surface
for edge in (outer, inner):                   # crisp rim lines
    d="M"+" L".join(f"{x:.1f},{y:.1f}" for x,y,_ in edge)
    A(f'<path d="{d}" fill="none" stroke="{C["coraldk"]}" stroke-width="2"/>')
# lane dashes along the centre line
d="M"+" L".join(f"{proj(X,Z)[0]:.1f},{proj(X,Z)[1]:.1f}" for X,Z in cen)
A(f'<path d="{d}" fill="none" stroke="#ffffff" stroke-width="1.6" stroke-dasharray="10 14" opacity="0.55"/>')

def flat(x,y,sc,ang_deg=0):
    """SVG matrix laying an upright glyph flat on the ground at screen point x,y."""
    r=math.radians(ang_deg)
    ux,uy = math.cos(r)*sc, -K*math.sin(r)*sc
    vx,vy = math.sin(r)*sc,  K*math.cos(r)*sc
    return f"matrix({ux:.4f} {uy:.4f} {vx:.4f} {vy:.4f} {x:.1f} {y:.1f})"
# label follows the track on the visible near-right stretch
lp=[proj(*lem(math.radians(d))) for d in [x/2 for x in range(630,712)]]
A('<path id="lane" fill="none" d="M'+" L".join(f"{x:.1f},{y:.1f}" for x,y,_ in lp)+'"/>')
A(f'<text font-family="{FONT}" font-weight="900" font-size="27" fill="#ffffff" letter-spacing="2" dy="9">'
  f'<textPath href="#lane" startOffset="50%" text-anchor="middle">DEVSECOPS</textPath></text>')
for deg,name in [(148,"code"),(160,"settings"),(172,"lock"),(184,"shield"),(230,"device-desktop-analytics"),(50,"rocket")]:
    X,Z=lem(math.radians(deg)); x,y,sc=proj(X,Z)
    s_ic=open(ICON+name+".svg").read()
    paths="".join(re.findall(r"<(?:path|circle|rect|line|polyline|ellipse)(?![^>]*stroke=\"none\")[^>]*/>",s_ic))
    A(f'<g transform="{flat(x,y,sc*2.7)}"><g transform="translate(-12,-12)" fill="none" stroke="#ffffff" '
      f'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">{paths}</g></g>')

# ---------- dashed pair lines (behind everything), broken around the agile mark
def dash(x1,x2,y):
    A(f'<line x1="{x1}" y1="{y}" x2="{x2}" y2="{y}" stroke="{C["gray"]}" stroke-width="1.6" stroke-dasharray="7 6"/>')
dash(130+BW,1200,339)
dash(235+BW,670,459); dash(930,1095,459)
dash(340+BW,690,579); dash(910,990,579)

# ---------- MBSE model panel
px,py,pw,ph=640,55,320,200
A(f'<rect x="{px-6}" y="{py-6}" width="{pw+12}" height="{ph+12}" rx="10" fill="{C["purple"]}" opacity="0.18" filter="url(#glow)"/>')
A(f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="8" fill="{C["purplebg"]}" stroke="{C["purple"]}" stroke-width="2.5"/>')
boxes=[(668,80,64,30),(760,72,64,26),(860,82,70,30),(690,140,70,30),(785,128,60,30),(870,148,62,30),(720,200,70,30),(830,196,64,30)]
for (bx,by,bw,bh) in boxes:
    A(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="2" fill="#ffffff" stroke="{C["purpledk"]}" stroke-width="1.4"/>')
    A(f'<line x1="{bx+6}" y1="{by+10}" x2="{bx+bw-6}" y2="{by+10}" stroke="{C["purpledk"]}" stroke-width="1" opacity="0.6"/>')
for (x1,y1,x2,y2) in [(732,95,760,85),(824,85,860,97),(700,110,725,140),(760,155,785,143),(845,143,870,163),(815,158,815,196),(755,170,755,200),(895,112,900,148),(790,213,830,211)]:
    A(f'<path d="M{x1},{y1} L{(x1+x2)/2},{y1} L{(x1+x2)/2},{y2} L{x2},{y2}" fill="none" stroke="{C["purpledk"]}" stroke-width="1.2"/>')
    A(f'<circle cx="{x2}" cy="{y2}" r="2.6" fill="#ffffff" stroke="{C["purpledk"]}" stroke-width="1.2"/>')
A(f'<text x="800" y="288" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="24" fill="{C["ink"]}">MBSE MODEL</text>')

# ---------- purple cables (digital thread) with connectors
def cable(sx,sy,tx,ty,c1x):
    d=f"M{sx},{sy} C{c1x},{sy} {tx},{sy+(ty-sy)*0.35} {tx},{ty-10}"
    A(f'<path d="{d}" fill="none" stroke="{C["purple"]}" stroke-width="9" opacity="0.22"/>')
    A(f'<path d="{d}" fill="none" stroke="{C["purple"]}" stroke-width="4.5" stroke-linecap="round"/>')
    A(f'<rect x="{tx-8}" y="{ty-16}" width="16" height="18" rx="3" fill="{C["purple"]}" stroke="{C["purpledk"]}" stroke-width="1.5"/>')
A(f'<rect x="{px-14}" y="118" width="16" height="44" rx="3" fill="{C["purple"]}"/>')
A(f'<rect x="{px+pw-2}" y="118" width="16" height="44" rx="3" fill="{C["purple"]}"/>')
cable(px-14,124,190,300,420); cable(px-14,134,265,300,470)
cable(px-14,146,360,420,500); cable(px-14,156,470,540,560)
cable(px+pw+14,124,1410,300,1180); cable(px+pw+14,134,1335,300,1130)
cable(px+pw+14,146,1240,420,1100); cable(px+pw+14,156,1130,540,1040)

# ---------- blocks and flow arrows
for (lab,x,y) in L: slab(x,y,BW,BH,lab,C["bluebg"],C["blue"],C["bluedk"])
for (lab,x,y) in R: slab(x,y,BW,BH,lab,C["greenbg"],C["green"],C["greendk"])
def arrow(x1,y1,x2,y2):
    A(f'<path d="M{x1},{y1} L{x2},{y2}" stroke="{C["gray"]}" stroke-width="2.5" fill="none" marker-end="url(#ah)"/>')
arrow(330,384,352,412); arrow(435,504,457,532); arrow(540,624,652,648)
arrow(948,648,1050,626); arrow(1150,532,1172,506); arrow(1255,412,1277,386)

# BUILD block (trapezoid slab)
A(f'<path d="M626,636 L974,636 L800,756 Z" fill="{C["builddk"]}" opacity="0.5" transform="translate(-10,10)"/>')
A(f'<path d="M626,636 L974,636 L800,756 Z" fill="{C["buildbg"]}" stroke="{C["builddk"]}" stroke-width="2" stroke-linejoin="round"/>')
A(f'<text x="800" y="676" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="28" fill="#3A3A38">BUILD</text>')

# ---------- agile increments
A(f'<text x="800" y="452" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="20" fill="{C["ink"]}">AGILE INCREMENTS</text>')
for k,(hw,top,bot) in enumerate([(120,478,612),(88,478,580),(56,478,548)]):
    A(f'<path d="M{800-hw},{top} L800,{bot} L{800+hw},{top}" fill="none" stroke="{C["gold"]}" '
      f'stroke-width="{18-k*3}" stroke-linejoin="miter" opacity="{0.95-k*0.15}"/>')
    A(f'<path d="M{800-hw},{top} L800,{bot} L{800+hw},{top}" fill="none" stroke="{C["goldbg"]}" stroke-width="{7-k*2}" stroke-linejoin="miter"/>')
A(icon("refresh", 950, 488, 46, C["gold"], 2.4))

# ---------- DevSecOps infinity loop
# ---------- digital twin (real satellite + cyan hologram) and feedback arrow
def satellite(x,y,rot,body,panel,line,dish,holo=False):
    g=[f'<g transform="translate({x},{y}) rotate({rot})">']
    sw="1.6"
    for sx in (-118,40):
        g.append(f'<rect x="{sx}" y="-18" width="78" height="36" fill="{panel}" stroke="{line}" stroke-width="{sw}"/>')
        for k in range(1,4): g.append(f'<line x1="{sx+k*19.5}" y1="-18" x2="{sx+k*19.5}" y2="18" stroke="{line}" stroke-width="1"/>')
        g.append(f'<line x1="{sx}" y1="0" x2="{sx+78}" y2="0" stroke="{line}" stroke-width="1"/>')
    g.append(f'<line x1="-40" y1="0" x2="40" y2="0" stroke="{line}" stroke-width="3"/>')
    g.append(f'<rect x="-24" y="-30" width="48" height="60" rx="6" fill="{body}" stroke="{line}" stroke-width="{sw}"/>')
    for k in (-14,0,14): g.append(f'<line x1="-24" y1="{k}" x2="24" y2="{k}" stroke="{line}" stroke-width="1" opacity="0.7"/>')
    g.append(f'<path d="M-14,30 L-22,52 M14,30 L22,52" stroke="{line}" stroke-width="2"/>')
    g.append(f'<ellipse cx="0" cy="56" rx="26" ry="9" fill="{dish}" stroke="{line}" stroke-width="{sw}"/>')
    g.append('</g>')
    A("".join(g))
satellite(1300,105,-22,"#C9CDD3","#3E5C94","#2A3445","#B8BDC5")
satellite(1480,120,-22,"#E3F7FA","#C7EEF4",C["cyan"],"#E3F7FA",holo=True)
for i in range(26):
    x=1352+i*4.2+(i%3)*3; y=95+((i*37)%50)-12
    A(f'<rect x="{x:.0f}" y="{y}" width="{3+(i%2)}" height="{3+(i%2)}" fill="{C["cyan"]}" opacity="{0.35+0.025*i:.2f}"/>')
A(f'<text x="1440" y="40" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="24" fill="{C["ink"]}">DIGITAL TWIN</text>')
A(f'<path d="M1212,80 L1170,26 L120,26 Q60,26 60,86 L60,399 Q60,459 120,459 L216,459" fill="none" stroke="{C["cyan"]}" '
  f'stroke-width="3.5" stroke-dasharray="11 8" marker-end="url(#ahc)"/>')
A('</svg>')
open(sys.argv[1] if len(sys.argv) > 1 else "mbse-devsecops-agile.svg","w").write("\n".join(out))
print("ok")
