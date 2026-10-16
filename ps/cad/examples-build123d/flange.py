from build123d import *
with BuildPart() as p:
    Box(100, 60, 20)
    fillet(p.edges().filter_by(Axis.Z), radius=8)
    with BuildSketch(p.faces().sort_by(Axis.Z)[-1]):
        with Locations((0, 0)):
            Circle(14)
    extrude(amount=25)
    with Locations(p.faces().sort_by(Axis.Z)[-1]):
        Hole(8)
    with Locations(p.faces().filter_by(Axis.Z).sort_by(Axis.Z)[1]):
        with GridLocations(76, 40, 2, 2):
            CounterBoreHole(radius=3.3, counter_bore_radius=5.5, counter_bore_depth=5)
    chamfer(p.edges().group_by(Axis.Z)[-1], length=1.5)
export_stl(p.part, "flange.stl", tolerance=0.02, angular_tolerance=0.1)
bb = p.part.bounding_box(); print(bb.min, bb.max, len(p.part.faces()))
