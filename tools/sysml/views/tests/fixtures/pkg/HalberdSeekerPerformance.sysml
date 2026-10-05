package HalberdSeekerPerformance {
    doc /* Seeker performance data. */
    private import ISQ::*;
    private import SecMeta::*;
    private import HalberdInterfaces::*;
    @Marking { level = Level::ITAR; }
    part def SeekerProfile { attribute acquisitionRange : LengthValue; port reports : TrackReportPort; }
}
