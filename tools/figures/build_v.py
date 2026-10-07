# build_v.py -- draws docs/img/mbse-devsecops-agile-v.svg: the systems V (needs .. operations) with the MBSE model and
# its digital thread, the glowing V, agile increments, the DevSecOps loop, and the digital twin (the fielded observing
# network -- weather station, network hub, data center -- and its simulation) feeding back into the left arm.
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
# ---------- glowing background V: U-shaped arms rising above NEEDS and OPERATIONS, V down to BUILD
# Stacked translucent strokes instead of an SVG blur filter, so the glow survives PDF and print.
GLOW_PATH=("M265,205 L265,262 Q265,330 322,378 L800,742 "
           "L1278,378 Q1335,330 1335,262 L1335,205")
GLOW_STEPS=24
for k in range(GLOW_STEPS):                      # wide/faint -> narrow/bright, many steps to avoid banding
    f=k/(GLOW_STEPS-1)
    w=250*(1-f)**1.6+6
    op=0.035+0.30*f**2.2
    r,g,b=255, int(210+45*f), int(63+180*f)       # deep yellow at the edge -> near white in the core
    A(f'<path d="{GLOW_PATH}" fill="none" stroke="#{r:02X}{g:02X}{b:02X}" stroke-width="{w:.1f}" '
      f'stroke-opacity="{op:.3f}" stroke-linecap="round" stroke-linejoin="round"/>')
for r,op in [(120,0.06),(90,0.08),(64,0.11),(40,0.16),(20,0.26)]:     # brightest where the V meets BUILD
    A(f'<circle cx="800" cy="742" r="{r}" fill="#FFE47F" opacity="{op}"/>')


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
cx,cy=800,400           # screen position of the track centre
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
# label follows the strand that runs through the crossing, between the model and the agile mark
lp=[proj(*lem(math.radians(d))) for d in [x/2 for x in range(452,540)]]
LABEL_DROP=9   # baseline sits this far below the lane centre so the capitals are centred on the band
A('<path id="lane" fill="none" d="M'+" L".join(f"{x:.1f},{y+LABEL_DROP:.1f}" for x,y,_ in lp)+'"/>')
A(f'<text font-family="{FONT}" font-weight="900" font-size="24" fill="#ffffff" letter-spacing="2">'
  f'<textPath href="#lane" startOffset="50%" text-anchor="middle">DEVSECOPS</textPath></text>')
for deg,name in [(158,"code"),(171,"settings"),(338,"lock"),(351,"shield"),(42,"device-desktop-analytics"),(218,"rocket")]:
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
cable(px-14,128,265,300,440)
cable(px-14,140,455,420,520); cable(px-14,152,560,540,590)
cable(px+pw+14,128,1335,300,1040)
cable(px+pw+14,140,1145,420,1080); cable(px+pw+14,152,1040,540,1010)

# ---------- blocks and flow arrows
for (lab,x,y) in L: slab(x,y,BW,BH,lab,C["bluebg"],C["blue"],C["bluedk"])
for (lab,x,y) in R: slab(x,y,BW,BH,lab,C["greenbg"],C["green"],C["greendk"])
def arrow(x1,y1,x2,y2):
    A(f'<path d="M{x1},{y1} L{x2},{y2}" stroke="{C["gray"]}" stroke-width="2.5" fill="none" marker-end="url(#ah)"/>')
# arrow(330,384,352,412); arrow(435,504,457,532); arrow(540,624,652,648)
# arrow(948,648,1050,626); arrow(1150,532,1172,506); arrow(1255,412,1277,386)

# BUILD block (trapezoid slab)
A(f'<path d="M626,636 L974,636 L800,756 Z" fill="{C["builddk"]}" opacity="0.5" transform="translate(-10,10)"/>')
A(f'<path d="M626,636 L974,636 L800,756 Z" fill="{C["buildbg"]}" stroke="{C["builddk"]}" stroke-width="2" stroke-linejoin="round"/>')
A(f'<text x="800" y="676" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="28" fill="#3A3A38">BUILD</text>')

# ---------- agile increments
A('<rect x="690" y="431" width="220" height="30" rx="15" fill="#ffffff" opacity="0.92"/>')
A(f'<text x="800" y="452" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="20" fill="{C["ink"]}">AGILE INCREMENTS</text>')
for k,(hw,top,bot) in enumerate([(120,478,612),(88,478,580),(56,478,548)]):
    A(f'<path d="M{800-hw},{top} L800,{bot} L{800+hw},{top}" fill="none" stroke="{C["gold"]}" '
      f'stroke-width="{18-k*3}" stroke-linejoin="miter" opacity="{0.95-k*0.15}"/>')
    A(f'<path d="M{800-hw},{top} L800,{bot} L{800+hw},{top}" fill="none" stroke="{C["goldbg"]}" stroke-width="{7-k*2}" stroke-linejoin="miter"/>')
A(icon("refresh", 950, 488, 46, C["gold"], 2.4))

# ---------- DevSecOps infinity loop
# ---------- digital twin (the fielded observing network + its cyan wireframe simulation) and feedback arrow
def trio(x, g, real=True):
    """The fielded system on a ground line at height g: weather station -> network hub -> data center.
    real=True draws the physical system; real=False draws its cyan wireframe twin."""
    if real:
        ln, bld, face, body, gnd, lw = "#2A3445", "#C9CDD3", "#3E5C94", "#F4F5F7", "#9A9A94", 1.6
    else:
        ln, bld, face, body, gnd, lw = C["cyan"], "#E3F7FA", "#C7EEF4", "#E3F7FA", C["cyan"], 1.4
    o=[]
    o.append(f'<line x1="{x-6}" y1="{g}" x2="{x+186}" y2="{g}" stroke="{gnd}" stroke-width="2"/>')
    # 1. weather station: mast, anemometer cups, wind vane, solar panel, sensor box
    o.append(f'<line x1="{x+24}" y1="{g}" x2="{x+24}" y2="{g-66}" stroke="{ln}" stroke-width="{lw+0.6}"/>')
    o.append(f'<line x1="{x+12}" y1="{g-66}" x2="{x+36}" y2="{g-66}" stroke="{ln}" stroke-width="{lw}"/>')
    for cx_ in (x+12, x+36): o.append(f'<path d="M{cx_-4},{g-66} A4,4 0 0 1 {cx_+4},{g-66}" fill="{body}" stroke="{ln}" stroke-width="{lw}"/>')
    o.append(f'<path d="M{x+24},{g-58} L{x+44},{g-58} L{x+48},{g-62} L{x+48},{g-54} Z" fill="{body}" stroke="{ln}" stroke-width="1"/>')
    o.append(f'<path d="M{x+24},{g-34} L{x+4},{g-44} L{x+4},{g-30} L{x+24},{g-22} Z" fill="{face}" stroke="{ln}" stroke-width="{lw}"/>')
    o.append(f'<rect x="{x+28}" y="{g-24}" width="16" height="14" fill="{bld}" stroke="{ln}" stroke-width="{lw}"/>')
    # 2. network hub: low building with a dish and an antenna
    o.append(f'<rect x="{x+66}" y="{g-24}" width="44" height="24" fill="{bld}" stroke="{ln}" stroke-width="{lw}"/>')
    for k in range(3):
        o.append(f'<rect x="{x+71+k*13}" y="{g-17}" width="8" height="6" fill="{face}" stroke="{ln}" stroke-width="0.8"/>')
    o.append(f'<line x1="{x+88}" y1="{g-24}" x2="{x+88}" y2="{g-38}" stroke="{ln}" stroke-width="{lw}"/>')
    o.append(f'<path d="M{x+76},{g-46} Q{x+88},{g-30} {x+100},{g-46}" fill="{body}" stroke="{ln}" stroke-width="{lw}"/>')
    o.append(f'<line x1="{x+88}" y1="{g-38}" x2="{x+92}" y2="{g-50}" stroke="{ln}" stroke-width="1"/>')
    # 3. data center: building with server racks
    o.append(f'<rect x="{x+126}" y="{g-52}" width="50" height="52" fill="{bld}" stroke="{ln}" stroke-width="{lw}"/>')
    for k in range(3):
        rx=x+131+k*15
        o.append(f'<rect x="{rx}" y="{g-46}" width="11" height="40" fill="{body}" stroke="{ln}" stroke-width="0.9"/>')
        for j in range(4): o.append(f'<line x1="{rx+2}" y1="{g-40+j*9}" x2="{rx+9}" y2="{g-40+j*9}" stroke="{face}" stroke-width="1.6"/>')
    # data links: station -> hub -> data center
    for x1,y1,x2,y2 in ((x+46,g-44,x+74,g-44),(x+102,g-44,x+126,g-44)):
        o.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{ln}" stroke-width="1.3" stroke-dasharray="3 3"/>')
    A("".join(o))
trio(1206, 124, real=True)
trio(1412, 206, real=False)
for i in range(18):
    x=1398+i*1.2+(i%3)*3; y=112+i*3.6+((i*37)%9)-4
    A(f'<rect x="{x:.0f}" y="{y}" width="{3+(i%2)}" height="{3+(i%2)}" fill="{C["cyan"]}" opacity="{0.4+0.03*i:.2f}"/>')
A(f'<text x="1392" y="40" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="24" fill="{C["ink"]}">DIGITAL TWIN</text>')
A(f'<text x="1298" y="154" text-anchor="middle" font-family="{FONT}" font-weight="700" font-size="17" fill="#55606C">station · network · data center</text>')
A(f'<text x="1504" y="236" text-anchor="middle" font-family="{FONT}" font-weight="700" font-size="17" fill="{C["cyan"]}">simulation</text>')
A(f'<path d="M1196,92 L1166,26 L120,26 Q60,26 60,86 L60,399 Q60,459 120,459 L216,459" fill="none" stroke="{C["cyan"]}" '
  f'stroke-width="3.5" stroke-dasharray="11 8" marker-end="url(#ahc)"/>')
A('</svg>')
open(sys.argv[1] if len(sys.argv) > 1 else "mbse-devsecops-agile.svg","w").write("\n".join(out))
print("ok")
