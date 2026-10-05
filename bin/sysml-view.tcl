#!/usr/bin/env wish
# sysml-view.tcl -- a live SysML v2 diagram beside Vim. Tcl/Tk as shipped with Git for Windows (mingw64/bin/wish.exe),
# nothing installed. The drawing is done by the kit's Perl drawers (tools/sysml/views/sysml-*-svg.pl); Tk 8.6 cannot show
# SVG, so tools/sysml/views/svg2tk.pl turns each SVG into canvas primitives and this window draws them.
#
#   wish bin/sysml-view.tcl [PROJECT-DIR] [--view tree|trace|ibd|pkg] [--root NAME]
#   wish bin/sysml-view.tcl PROJECT-DIR --view V --export-ps FILE      (draw once, write PostScript, exit: tests, printing)
#
# PROJECT-DIR holds model/ (default: the nearest directory upward from here that does). Save a .sysml file in Vim and
# the diagram redraws within a second or two. Vim's \mf writes the definition under the cursor to ~/.sysml-view/focus:
# the viewer highlights it and scrolls to it (with "follow" on, an IBD redraws rooted at it). Click a box: its file:line
# goes to the clipboard and to ~/.sysml-view/jump, and Vim's \mo opens it there.
#
# Keys: 1-4 view (tree trace ibd pkg), + / - zoom, 0 fit, r redraw, q quit. Wheel zooms, drag pans.

package require Tk
set kit [file normalize [file join [file dirname [info script]] ..]]
set perl [expr {[info exists env(PERL)] ? $env(PERL) : "perl"}]
array set opt {view tree root "" project "" export ""}
set argv2 $argv
while {[llength $argv2]} {
    set a [lindex $argv2 0]; set argv2 [lrange $argv2 1 end]
    switch -- $a {
        --view      { set opt(view) [lindex $argv2 0]; set argv2 [lrange $argv2 1 end] }
        --root      { set opt(root) [lindex $argv2 0]; set argv2 [lrange $argv2 1 end] }
        --export-ps { set opt(export) [lindex $argv2 0]; set argv2 [lrange $argv2 1 end] }
        default     { set opt(project) $a }
    }
}
proc find_project {start} {
    set d [file normalize $start]
    while 1 {
        if {[file isdirectory [file join $d model]]} { return $d }
        set up [file dirname $d]
        if {$up eq $d} { return "" }
        set d $up
    }
}
if {$opt(project) eq ""} { set opt(project) [find_project [pwd]] }
if {$opt(project) eq "" || ![file isdirectory [file join $opt(project) model]]} {
    set opt(project) [file join $kit examples halberd]
}
set model [file join $opt(project) model]
set state [file join [expr {[info exists env(HOME)] ? $env(HOME) : $kit}] .sysml-view]
file mkdir $state
set tmp [file join $state "view.svg"]

# ---------------------------------------------------------------- window
wm title . "SysML view -- [file tail $opt(project)]"
ttk::frame .bar
foreach {v label} {tree Tree trace Trace ibd IBD pkg Packages} {
    ttk::radiobutton .bar.$v -text $label -value $v -variable opt(view) -command redraw
    pack .bar.$v -side left -padx 2
}
ttk::label .bar.rl -text "  root:"
ttk::entry .bar.root -textvariable opt(root) -width 22
bind .bar.root <Return> redraw
set follow 0
ttk::checkbutton .bar.follow -text follow -variable follow
ttk::button .bar.fit -text Fit -command {fit}
ttk::button .bar.in -text + -width 2 -command {zoom 1.25}
ttk::button .bar.out -text - -width 2 -command {zoom 0.8}
ttk::button .bar.ps -text Print -command printps
pack .bar.rl .bar.root .bar.follow -side left
pack .bar.ps .bar.out .bar.in .bar.fit -side right -padx 2
pack .bar -side top -fill x -pady 2
canvas .c -background white -xscrollcommand {.h set} -yscrollcommand {.v set} -highlightthickness 0
ttk::scrollbar .h -orient horizontal -command {.c xview}
ttk::scrollbar .v -orient vertical -command {.c yview}
ttk::label .status -anchor w -relief sunken
pack .status -side bottom -fill x
pack .h -side bottom -fill x
pack .v -side right -fill y
pack .c -side left -fill both -expand 1
wm geometry . 1100x800

set prims {}; set size {800 600}; set z 1.0; set sig ""; set focus ""; set focusmt 0
array set titles {}
set mono [expr {[lsearch -exact [font families] Consolas] >= 0 ? "Consolas" : "Courier"}]

# ---------------------------------------------------------------- render: Perl drawer -> SVG -> primitives
proc render {} {
    global perl kit model tmp opt prims size titles
    set tool [file join $kit tools sysml views sysml-$opt(view)-svg.pl]
    set args [list -o $tmp]
    if {$opt(root) ne "" && $opt(view) in {tree ibd}} { lappend args --root $opt(root) }
    if {$opt(root) ne "" && $opt(view) eq "trace"} { lappend args --match $opt(root) }
    if {[catch {exec $perl $tool {*}$args $model 2>@1} out]} {
        if {![file exists $tmp]} { .status configure -text "drawer failed: [string range $out 0 300]"; return 0 }
    }
    if {[catch {exec $perl [file join $kit tools sysml views svg2tk.pl] $tmp} tk]} {
        .status configure -text "svg2tk failed: [string range $tk 0 300]"; return 0
    }
    set prims {}; array unset titles
    foreach line [split $tk \n] {
        if {$line eq ""} continue
        set kind [lindex $line 0]
        if {$kind eq "size"} { set size [lrange $line 1 2]; continue }
        if {$kind eq "title"} { set titles([lindex $line 1]) [lindex $line 2]; continue }
        lappend prims $line
    }
    .status configure -text "[llength $prims] item(s) -- [lindex [split $out \n] end]"
    return 1
}
proc draw {} {
    global prims z mono size
    .c delete all
    foreach p $prims {
        set k [lindex $p 0]
        switch -- $k {
            rect {
                lassign $p - x0 y0 x1 y1 fill out w dash g
                set id [.c create rectangle [expr {$x0*$z}] [expr {$y0*$z}] [expr {$x1*$z}] [expr {$y1*$z}] \
                    -fill $fill -outline $out -width [expr {max(1,$w*$z)}] -tags [list $g shape]]
                if {[llength $dash]} { .c itemconfigure $id -dash $dash }
            }
            line {
                lassign $p - pts col w dash arrow g
                set sp {}; foreach v $pts { lappend sp [expr {$v*$z}] }
                set id [.c create line {*}$sp -fill $col -width [expr {max(1,$w*$z)}] -arrow $arrow -tags [list $g]]
                if {[llength $dash]} { .c itemconfigure $id -dash $dash }
            }
            poly {
                lassign $p - pts fill out w g
                set sp {}; foreach v $pts { lappend sp [expr {$v*$z}] }
                .c create polygon {*}$sp -fill $fill -outline $out -width [expr {max(1,$w*$z)}] -tags [list $g]
            }
            text {
                lassign $p - x y anchor fs weight slant col g str
                set px [expr {max(4, int($fs*$z+0.5))}]
                .c create text [expr {$x*$z}] [expr {$y*$z}] -anchor $anchor -text $str -fill $col \
                    -font [list $mono -$px $weight $slant] -tags [list $g]
            }
        }
    }
    .c configure -scrollregion [list 0 0 [expr {[lindex $size 0]*$z}] [expr {[lindex $size 1]*$z}]]
    highlight
}
proc redraw {} { if {[render]} draw }
proc zoom {f} { global z; set z [expr {max(0.1, min(6.0, $z*$f))}]; draw }
proc fit {} {
    global z size
    update idletasks
    set z [expr {min(([winfo width .c]-10.0)/[lindex $size 0], ([winfo height .c]-10.0)/[lindex $size 1])}]
    draw
}

# ---------------------------------------------------------------- the link with Vim
proc group_at {x y} {
    foreach id [lreverse [.c find overlapping [expr {$x-1}] [expr {$y-1}] [expr {$x+1}] [expr {$y+1}]]] {
        foreach t [.c gettags $id] { if {[string match g* $t] && [info exists ::titles($t)]} { return $t } }
    }
    return ""
}
proc where {title} { if {[regexp {(\S+\.(?:sysml|kerml)):(\d+)} $title -> f l]} { return "$f:$l" }; return "" }
bind .c <Motion> {
    set g [group_at [.c canvasx %x] [.c canvasy %y]]
    if {$g ne ""} { .status configure -text $titles($g) }
}
bind .c <Button-1> {
    set g [group_at [.c canvasx %x] [.c canvasy %y]]
    if {$g ne ""} {
        set w [where $titles($g)]
        if {$w ne ""} {
            clipboard clear; clipboard append $w
            set fh [open [file join $state jump] w]; puts $fh [file join $opt(project) .. $w]; close $fh
            .status configure -text "$w  (copied; \\mo in Vim opens it)"
        }
    }
}
proc highlight {} {
    global focus titles
    .c delete hl
    if {$focus eq ""} return
    set first ""
    foreach g [array names titles] {
        if {[regexp "(^|\[^A-Za-z0-9_\])[string map {. \\. :: ::} $focus](\[^A-Za-z0-9_\]|$)" $titles($g)]} {
            foreach id [.c find withtag $g] {
                if {[.c type $id] eq "rectangle"} {
                    lassign [.c coords $id] x0 y0 x1 y1
                    .c create rectangle [expr {$x0-3}] [expr {$y0-3}] [expr {$x1+3}] [expr {$y1+3}] -outline black -width 3 -tags hl
                    if {$first eq ""} { set first [list $x0 $y0] }
                    break
                }
            }
        }
    }
    if {$first ne ""} {
        lassign [.c cget -scrollregion] - - W H
        if {$W > 0 && $H > 0} {
            .c xview moveto [expr {max(0, ([lindex $first 0] - [winfo width .c]/3.0) / $W)}]
            .c yview moveto [expr {max(0, ([lindex $first 1] - [winfo height .c]/3.0) / $H)}]
        }
    }
}

# ---------------------------------------------------------------- watching: the model and Vim's focus
proc model_sig {} {
    global model
    set s {}
    set dirs [list $model]
    while {[llength $dirs]} {
        set d [lindex $dirs 0]; set dirs [lrange $dirs 1 end]
        foreach f [glob -nocomplain -directory $d *] {
            if {[file isdirectory $f]} { lappend dirs $f } elseif {[string match *.sysml $f] || [string match *.kerml $f]} { lappend s "$f:[file mtime $f]" }
        }
    }
    return [join [lsort $s] " "]
}
proc watch {} {
    global sig state focus focusmt follow opt
    set s [model_sig]
    if {$s ne $sig} { set sig $s; redraw }
    set ff [file join $state focus]
    if {[file exists $ff] && [file mtime $ff] != $focusmt} {
        set focusmt [file mtime $ff]
        set fh [open $ff]; set f [string trim [read $fh]]; close $fh
        if {$f ne $focus} {
            set focus $f
            if {$follow && $opt(view) eq "ibd"} { set opt(root) $f; redraw } else { highlight }
        }
    }
    after 1000 watch
}

proc printps {} {
    set f [tk_getSaveFile -defaultextension .ps -filetypes {{PostScript .ps}} -title "Save the view as PostScript"]
    if {$f ne ""} { lassign [.c bbox all] x0 y0 x1 y1; .c postscript -file $f -x $x0 -y $y0 -width [expr {$x1-$x0}] -height [expr {$y1-$y0}] -pagewidth 10i -rotate [expr {$x1-$x0 > $y1-$y0}] }
}

# ---------------------------------------------------------------- keys and mouse
bind . <Key-1> {set opt(view) tree; redraw}
bind . <Key-2> {set opt(view) trace; redraw}
bind . <Key-3> {set opt(view) ibd; redraw}
bind . <Key-4> {set opt(view) pkg; redraw}
bind . <plus> {zoom 1.25}
bind . <equal> {zoom 1.25}
bind . <minus> {zoom 0.8}
bind . <Key-0> fit
bind . <Key-r> redraw
bind . <Key-q> exit
bind .c <MouseWheel> {zoom [expr {%D > 0 ? 1.1 : 0.9}]}
bind .c <Button-4> {zoom 1.1}
bind .c <Button-5> {zoom 0.9}
bind .c <ButtonPress-3> {.c scan mark %x %y}
bind .c <B3-Motion> {.c scan dragto %x %y 1}
bind .c <ButtonPress-2> {.c scan mark %x %y}
bind .c <B2-Motion> {.c scan dragto %x %y 1}

# ---------------------------------------------------------------- go
if {$opt(export) ne ""} {
    if {![render]} { puts stderr [.status cget -text]; exit 1 }
    set z 1.0; draw; update
    lassign [.c bbox all] x0 y0 x1 y1
    .c postscript -file $opt(export) -x $x0 -y $y0 -width [expr {$x1-$x0}] -height [expr {$y1-$y0}]
    puts "sysml-view: [llength $prims] item(s), [array size titles] element(s) -> $opt(export)"
    exit 0
}
set sig [model_sig]
redraw
after 300 fit
after 1000 watch
