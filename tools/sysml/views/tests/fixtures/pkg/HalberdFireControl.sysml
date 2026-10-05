package HalberdFireControl {
    doc /* Fire control segment. */
    private import SecMeta::*;
    private import HalberdInterfaces::*;
    @Marking { level = Level::CUI; }
    part def FireControlSegment {
        port fromSensors : ~TrackReportPort;
        part countermeasures : HalberdThreats::JammerModel;
    }
    package Software {
        doc /* Nested package; inherits CUI. */
        part def Tracker;
    }
}
