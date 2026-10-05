package HalberdInterfaces {
    doc /* Shared messages and ports. U, so everyone can import it. */
    private import SecMeta::*;
    @Marking { level = Level::U; }
    item def TrackReport;
    port def TrackReportPort { out item report : TrackReport; }
}
