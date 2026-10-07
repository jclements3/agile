# build_extra_figs.py -- draws docs/img/recipe-anatomy.svg (the recipe example split into its colored fields) and
# docs/img/building-blocks.svg (the core SE building blocks and their relationships), each also as .pdf and .png.
# Needs Python 3 and cairosvg (pip install cairosvg). Writes into the current directory:
#   cd docs/img && python3 ../../tools/figures/build_extra_figs.py   (then delete the .pdf/.png if you only want the SVGs)
# Not part of the core-Perl kit: the SVGs are committed.
import cairosvg
FONT="Inter, Helvetica, Arial, sans-serif"
CAT={  # category: (fill, stroke/text)
 "metadata":("#ECEEF1","#4B5563"),"state":("#FBF0D2","#8A6508"),"component":("#E3ECF6","#2F5D8A"),
 "function":("#FAE6DE","#A2492E"),"item":("#ECE8FC","#5B40C8"),"parameter":("#E0F2EA","#1F7A5A"),
 "interface":("#DDF3F7","#127F93"),"verb":("#FFFFFF","#16202B")}
def tw(s,size): return len(s)*size*0.56+2
# ---------- 1. recipe anatomy
chips=[("(U//FOUO)","1 Classification","metadata"),("While in normal flight mode","2–4 State","state"),
 ("except during the navigational upset condition","15 Exception","state"),("the navigation computer","5 Target","component"),
 ("shall","7 Operative verb","verb"),("send","8 Target verb","function"),("the guidance solution message","9 Object","item"),
 ("to the main computer","10–11 Destination","interface"),("within 30 msec","11 Threshold","parameter"),
 ("of the 10 Hz clock signal","3 Trigger","state"),("in accordance with Navigation Computer IRS (D12340000) §5.1.4","12–14 Specification","interface"),
 ("(NC_112358)","17 ID","metadata"),("[MC]","18 Tag","metadata")]
W=1600; x,y=40,60; rows=[]; o=[]
o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="HH" viewBox="0 0 {W} HH">')
o.append('<rect width="100%" height="100%" fill="#ffffff"/>')
H=58; gap=14
for text,label,cat in chips:
    w=max(tw(text,21),tw(label,15))+30
    if x+w>W-40: x=40; y+=H+46
    f,s=CAT[cat]
    o.append(f'<rect x="{x}" y="{y}" width="{w:.0f}" height="{H}" rx="8" fill="{f}" stroke="{s}" stroke-width="2"/>')
    o.append(f'<text x="{x+w/2:.0f}" y="{y+37}" text-anchor="middle" font-family="{FONT}" font-size="21" font-weight="600" fill="#16202B">{text}</text>')
    o.append(f'<text x="{x+w/2:.0f}" y="{y+H+24}" text-anchor="middle" font-family="{FONT}" font-size="15" font-weight="700" fill="{s}">{label}</text>')
    x+=w+gap
y+=H+60
# legend: building block per color
leg=[("metadata","Metadata / ID"),("state","State, trigger, exception"),("component","Component"),("function","Function"),
     ("item","Item"),("interface","Interface / spec"),("parameter","Parameter")]
x=40
for cat,lab in leg:
    f,s=CAT[cat]; w=tw(lab,16)+44
    o.append(f'<rect x="{x}" y="{y}" width="20" height="20" rx="4" fill="{f}" stroke="{s}" stroke-width="2"/>')
    o.append(f'<text x="{x+28}" y="{y+16}" font-family="{FONT}" font-size="16" fill="#3A4452">{lab}</text>')
    x+=w
y+=44
svg="\n".join(o).replace("HH",str(y))+"\n</svg>"
open("recipe-anatomy.svg","w").write(svg)
cairosvg.svg2pdf(bytestring=svg.encode(),write_to="recipe-anatomy.pdf")
cairosvg.svg2png(bytestring=svg.encode(),write_to="recipe-anatomy.png",output_width=1200)

# ---------- 2. building blocks graph
N={ "Need":(170,110,"metadata"),"Requirement":(520,110,"metadata"),"Decision":(860,110,"metadata"),
    "Verification case":(1200,110,"interface"),"Hazard":(1450,110,"state"),
    "Function":(170,300,"function"),"Component":(520,300,"component"),"Interface":(860,300,"interface"),"Item":(1200,300,"item"),
    "State / mode":(170,490,"state"),"Parameter":(520,490,"parameter"),"Constraint":(860,490,"parameter"),"Baseline":(1200,490,"metadata")}
BW,BH=210,60
o=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="560" viewBox="0 0 1600 560">','<rect width="100%" height="100%" fill="#ffffff"/>',
   '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="#6B7380"/></marker></defs>']
def lab(mx,my,t):
    w=tw(t,15)+14
    o.append(f'<rect x="{mx-w/2:.0f}" y="{my-12:.0f}" width="{w:.0f}" height="24" rx="12" fill="#ffffff" stroke="#D5DAE0"/>')
    o.append(f'<text x="{mx:.0f}" y="{my+5:.0f}" text-anchor="middle" font-family="{FONT}" font-size="15" font-style="italic" fill="#3A4452">{t}</text>')
def path(d,t,mx,my):
    o.append(f'<path d="{d}" fill="none" stroke="#6B7380" stroke-width="2" marker-end="url(#a)"/>'); lab(mx,my,t)
path("M275,110 L413,110","derives",344,110)
path("M755,110 L627,110","justifies",691,110)
path("M1200,80 C1200,30 560,30 540,78","verifies",880,42)
path("M560,80 C580,8 1440,8 1450,78","mitigates",1010,22)
path("M470,140 L255,268","allocates",362,204)
path("M520,140 L520,268","satisfies",520,204)
path("M415,300 L277,300","performs",346,300)
path("M625,300 L753,300","connects",689,300)
path("M965,300 L1093,300","carries",1029,300)
path("M170,330 L170,458","active in",170,394)
path("M600,140 C700,200 700,420 560,458","thresholds",668,300+90)
path("M625,490 L753,490","binds",689,490)
for n,(cx,cy,cat) in N.items():
    f,st=CAT[cat]
    o.append(f'<rect x="{cx-BW/2}" y="{cy-BH/2}" width="{BW}" height="{BH}" rx="8" fill="{f}" stroke="{st}" stroke-width="2"/>')
    o.append(f'<text x="{cx}" y="{cy+7}" text-anchor="middle" font-family="{FONT}" font-size="21" font-weight="700" fill="{st}">{n}</text>')
o.append(f'<text x="1200" y="545" text-anchor="middle" font-family="{FONT}" font-size="15" font-style="italic" fill="#55606C">versions any of the above</text>')
o.append("</svg>")
svg="\n".join(o)
open("building-blocks.svg","w").write(svg)
cairosvg.svg2pdf(bytestring=svg.encode(),write_to="building-blocks.pdf")
cairosvg.svg2png(bytestring=svg.encode(),write_to="building-blocks.png",output_width=1200)
print("ok")
