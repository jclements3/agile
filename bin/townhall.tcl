#!/usr/bin/env wish
# townhall.tcl -- the 15-minute meeting console. Tcl/Tk as shipped with Git for Windows (mingw64/bin/wish.exe),
# nothing installed. Tk draws the window; every decision is made by daily.pl, so the tests still cover the logic.
#
#   wish bin/townhall.tcl [PROJECT-DIR]        (from Git Bash:  wish ~/projects/agile/bin/townhall.tcl ~/projects/agile/data/lab)
#
# Left: the paste box. Ctrl-A, Ctrl-C in the Teams meeting chat, then Paste here (or Ctrl-V). Every paste is
# saved as standups/<today>-chat.txt and linted immediately: the right side shows one line per person
# (ERROR / warn / ok), the roster with who has answered, and the replies to send back. Buttons at the bottom
# run answers / compile / report / cockpit when the meeting ends. Nothing here posts to Teams: replies are
# copied to the clipboard, you paste them.

package require Tk

# ---------------------------------------------------------------- where things are
set KIT   [file dirname [file dirname [file normalize [info script]]]]
set PROJ  [expr {[llength $argv] ? [file normalize [lindex $argv 0]] : [pwd]}]
set DAILY [file join $KIT bin daily.pl]
# perl: from PATH under Git Bash; from a Windows shortcut, the one shipped beside wish.exe (Git for Windows: usr/bin/perl.exe)
set PERL perl
if {[catch {exec perl -e 1}]} { set p [file join [file dirname [file dirname [file dirname [info nameofexecutable]]]] usr bin perl.exe]; if {[file exists $p]} { set PERL $p } }
set TODAY [clock format [clock seconds] -format %Y-%m-%d]
if {![file exists [file join $PROJ scrum.conf]]} { tk_messageBox -icon error -message "No scrum.conf in $PROJ.\nStart with:  wish townhall.tcl PROJECT-DIR"; exit 1 }
set CHAT  [file join $PROJ standups $TODAY-chat.txt]
file mkdir [file join $PROJ standups]

proc daily {args} {                            ;# run daily.pl in the project, return stdout+stderr; exit code in ::rc
    global DAILY PROJ
    set ::rc 0
    if {[catch {exec $::PERL $DAILY --conf [file join $PROJ scrum.conf] {*}$args 2>@1} out opts]} {
        set ::rc [lindex [dict get $opts -errorcode] end]
        if {![string is integer -strict $::rc]} { set ::rc 1 }
        regsub {\n?child process exited abnormally\s*$} $out {} out   ;# a non-zero exit (lint with errors) is a result, not a failure
    }
    # daily.pl writes UTF-8 (the replies carry a thumbs-up); exec decoded it in the system code page -- undo that
    if {[catch {set out [encoding convertfrom utf-8 [encoding convertto [encoding system] $out]]}]} {}
    return $out
}

# ---------------------------------------------------------------- window
wm title . "Townhall $TODAY -- [file tail $PROJ]"
wm geometry . 1500x860
option add *Font {"Segoe UI" 10}
ttk::style configure Head.TLabel -font {"Segoe UI" 11 bold} -foreground #27235d
ttk::style configure Gold.TFrame -background #e6af22

ttk::frame .top -padding {10 6}
ttk::label .top.title -text "Townhall $TODAY  --  [file tail $PROJ]" -style Head.TLabel
ttk::label .top.hint -text "Ctrl-A, Ctrl-C in the meeting chat, then Paste. Lint runs on every paste." -foreground #808082
pack .top.title -side left
pack .top.hint -side left -padx 20
pack .top -fill x
ttk::frame .rule -height 3 -style Gold.TFrame
pack .rule -fill x

ttk::panedwindow .pw -orient horizontal
pack .pw -fill both -expand 1 -padx 8 -pady 6

# left: the paste box
ttk::frame .pw.l
ttk::label .pw.l.h -text "Meeting chat (pasted)" -style Head.TLabel
text .pw.l.t -wrap word -undo 1 -font {Consolas 10} -yscrollcommand {.pw.l.sb set}
ttk::scrollbar .pw.l.sb -command {.pw.l.t yview}
ttk::frame .pw.l.b
ttk::button .pw.l.b.paste -text "Paste from clipboard" -command paste_clip
ttk::button .pw.l.b.lint  -text "Lint now" -command lint_now
ttk::button .pw.l.b.clear -text "Clear" -command {.pw.l.t delete 1.0 end}
set ::LIVE 0
ttk::checkbutton .pw.l.b.live -text "Live: answers + cockpit after every paste (share dashboard.html with auto-reload on)" -variable ::LIVE
pack .pw.l.b.paste .pw.l.b.lint .pw.l.b.clear .pw.l.b.live -side left -padx 3
grid .pw.l.h  -row 0 -column 0 -sticky w -pady {0 4}
grid .pw.l.t  -row 1 -column 0 -sticky nsew
grid .pw.l.sb -row 1 -column 1 -sticky ns
grid .pw.l.b  -row 2 -column 0 -sticky w -pady 6
grid rowconfigure .pw.l 1 -weight 1
grid columnconfigure .pw.l 0 -weight 1
.pw add .pw.l -weight 1

# right: lint, roster, replies
ttk::frame .pw.r
ttk::label .pw.r.h1 -text "Lint" -style Head.TLabel
text .pw.r.lint -height 14 -wrap none -font {Consolas 10} -state disabled
.pw.r.lint tag configure ERROR -foreground #d03b3b -font {Consolas 10 bold}
.pw.r.lint tag configure warn  -foreground #b8860b
.pw.r.lint tag configure ok    -foreground #0ca30c
.pw.r.lint tag configure sum   -foreground #808082
ttk::label .pw.r.h2 -text "Replies: corrections, and a read-back of each clean status for a thumbs-up (copy, paste into the chat -- or 1:1)" -style Head.TLabel
text .pw.r.rep -height 9 -wrap word -font {"Segoe UI" 10} -state disabled
ttk::frame .pw.r.rb
ttk::button .pw.r.rb.copy -text "Copy replies to clipboard" -command copy_replies
ttk::button .pw.r.rb.priv -text "Private 1:1 page" -command {daily --today=$::TODAY lint --private --confirm; open_file [file join $::PROJ reports $::TODAY-lint.html]}
pack .pw.r.rb.copy .pw.r.rb.priv -side left -padx 3
ttk::label .pw.r.h3 -text "Roster" -style Head.TLabel
text .pw.r.ros -height 8 -wrap word -font {"Segoe UI" 10} -state disabled
.pw.r.ros tag configure yes -foreground #0ca30c
.pw.r.ros tag configure no  -foreground #d03b3b
grid .pw.r.h1   -row 0 -column 0 -sticky w
grid .pw.r.lint -row 1 -column 0 -sticky nsew
grid .pw.r.h2   -row 2 -column 0 -sticky w -pady {8 0}
grid .pw.r.rep  -row 3 -column 0 -sticky nsew
grid .pw.r.rb   -row 4 -column 0 -sticky w -pady 4
grid .pw.r.h3   -row 5 -column 0 -sticky w -pady {8 0}
grid .pw.r.ros  -row 6 -column 0 -sticky nsew
grid rowconfigure .pw.r 1 -weight 2
grid rowconfigure .pw.r 3 -weight 1
grid rowconfigure .pw.r 6 -weight 1
grid columnconfigure .pw.r 0 -weight 1
.pw add .pw.r -weight 1

# bottom: after the meeting
ttk::frame .bot -padding {8 4}
ttk::button .bot.propose -text "Propose (before)" -command {show_out [daily --today=$::TODAY propose]}
ttk::button .bot.answers -text "Answers" -command {show_out [daily --today=$::TODAY answers --guess]}
ttk::button .bot.assume  -text "Answers --assume" -command {show_out [daily --today=$::TODAY answers --guess --assume]}
ttk::button .bot.dry     -text "Dry compile" -command {show_out [daily --today=$::TODAY --dry compile]}
ttk::button .bot.compile -text "Compile" -command {show_out [daily --today=$::TODAY compile]}
ttk::button .bot.report  -text "Report" -command {show_out [daily --today=$::TODAY report]}
ttk::button .bot.cockpit -text "Cockpit" -command {show_out [exec $::PERL [file join $::KIT agile.pl] --no-open --today $::TODAY $::PROJ 2>@1]; open_file [file join $::KIT dashboard.html]}
ttk::button .bot.commit  -text "Commit" -command {show_out [daily --today=$::TODAY commit]}
ttk::label  .bot.status -text "" -foreground #808082
pack .bot.propose .bot.answers .bot.assume .bot.dry .bot.compile .bot.report .bot.cockpit .bot.commit -side left -padx 3
pack .bot.status -side left -padx 12
pack .bot -fill x

# output pane for the after-meeting commands
toplevel .out; wm withdraw .out; wm title .out "daily.pl output"
text .out.t -wrap none -font {Consolas 10} -yscrollcommand {.out.sb set}; ttk::scrollbar .out.sb -command {.out.t yview}
pack .out.sb -side right -fill y; pack .out.t -fill both -expand 1
wm geometry .out 900x600
proc show_out {text} { .out.t delete 1.0 end; .out.t insert end $text; wm deiconify .out; raise .out; .bot.status configure -text "rc=$::rc" }
proc open_file {f} { if {$::tcl_platform(platform) eq "windows"} { exec cmd /c start "" [file nativename $f] & } else { exec xdg-open $f & } }

# ---------------------------------------------------------------- lint on paste
proc paste_clip {} { if {![catch {clipboard get} c]} { .pw.l.t insert end $c\n; lint_now } }
bind .pw.l.t <<Paste>> {after 50 lint_now}
bind .pw.l.t <Control-v> {after 50 lint_now}
proc lint_now {} {
    global CHAT TODAY
    set fh [open $CHAT w]; fconfigure $fh -encoding utf-8; puts -nonewline $fh [.pw.l.t get 1.0 end]; close $fh
    set out [daily --today=$TODAY lint --table]
    .pw.r.lint configure -state normal; .pw.r.lint delete 1.0 end
    .pw.r.lint insert end [format "%-5s %-18s %-26s %-26s %-16s %s\n" STATE WHO YESTERDAY TODAY BLOCKERS NOTE] sum
    set answered {}; set n 0; set bad 0
    foreach line [split $out \n] {
        set f [split $line \t]
        if {[llength $f] < 5 || [lindex $f 0] eq "state"} continue
        lassign $f st who y t b note
        set tag [string map {warn warn} $st]
        .pw.r.lint insert end [format "%-5s %-18s %-26s %-26s %-16s %s\n" $st [string range $who 0 17] [string range $y 0 25] [string range $t 0 25] [string range $b 0 15] $note] $tag
        lappend answered $who; incr n; if {$st eq "ERROR"} { incr bad }
    }
    .pw.r.lint insert end "\n# $n answered, $bad with errors\n" sum
    .pw.r.lint configure -state disabled
    set rep [daily --today=$TODAY lint --reply --confirm]
    .pw.r.rep configure -state normal; .pw.r.rep delete 1.0 end; .pw.r.rep insert end $rep; .pw.r.rep configure -state disabled
    roster $answered
    after idle live_update
}
proc roster {answered} {
    global TODAY PROJ
    # roster.txt first (name | email | team | role | org); the journal's owners when there is no roster yet
    set people {}
    set rf [file join $PROJ roster.txt]
    if {[file exists $rf]} {
        set fh [open $rf r]; fconfigure $fh -encoding utf-8
        foreach line [split [read $fh] \n] {
            if {[regexp {^\s*(#|$)} $line]} continue
            set f [lmap x [split $line |] {string trim $x}]
            if {[llength $f] < 3} { set f [lmap x [split $line ,] {string trim $x}] }
            if {[lindex $f 0] ne ""} { lappend people [list [lindex $f 0] [lindex $f 2] [lindex $f 3]] }
        }
        close $fh
    } else {
        foreach line [split [daily members] \n] { if {[regexp {^(\S.*?) \((\w+)\)} $line -> who team]} { lappend people [list $who $team ""] } }
    }
    .pw.r.ros configure -state normal; .pw.r.ros delete 1.0 end
    set n 0; set yes 0; set lastteam ""
    foreach p [lsort -index 1 [lsort -index 0 $people]] {
        lassign $p who team role
        if {$team ne $lastteam} { .pw.r.ros insert end "\n$team:  " sum; set lastteam $team }
        incr n
        set tag [expr {[lsearch -exact $answered $who] >= 0 ? "yes" : "no"}]
        if {$tag eq "yes"} { incr yes }
        .pw.r.ros insert end [expr {$tag eq "yes" ? "\[x\] " : "\[ \] "}]$who[expr {$role ne "" ? " ($role)" : ""}]"   " $tag
    }
    .pw.r.ros insert end "\n\n$yes of $n answered" sum
    .pw.r.ros configure -state disabled
    .bot.status configure -text "$yes of $n answered -- chat saved to [file tail $::CHAT]"
}
proc copy_replies {} { clipboard clear; clipboard append [.pw.r.rep get 1.0 end]; .bot.status configure -text "replies copied" }
# live mode: after each lint, record the answers and rebuild the cockpit so a shared browser (auto-reload on) shows the day growing
proc live_update {} {
    if {!$::LIVE} return
    daily --today=$::TODAY answers --guess
    catch {exec $::PERL [file join $::KIT agile.pl] --no-open --today $::TODAY $::PROJ 2>@1}
    .bot.status configure -text "[.bot.status cget -text] -- cockpit rebuilt [clock format [clock seconds] -format %H:%M:%S]"
}

# load today's chat if it already exists (the console was restarted mid-meeting)
if {[file exists $CHAT]} { set fh [open $CHAT r]; fconfigure $fh -encoding utf-8; .pw.l.t insert end [read $fh]; close $fh; lint_now } else { roster {} }
