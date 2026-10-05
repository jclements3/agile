// Halberd -- a fictional, notional, unclassified interceptor program (an integrated air and
// missile defense capability) used as the running example of the agile kit. Structure only:
// no performance parameters, no design data, no real program information.
//
// Segment G (Government Program Office): the enterprise at the top of the part tree, the
// system requirements it satisfies, and the program phases.
package Enterprise {
    doc /* The Halberd enterprise: the six product segments and what each one satisfies. */
    private import Conventions::*;
    private import InterfaceDefinitions::*;
    private import SystemRequirements::**;
    private import Sensors::*;
    private import FireControl::*;
    private import Interceptor::*;
    private import Launch::*;
    private import Support::*;
    private import TestAndTraining::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    part def HalberdEnterprise {
        @L1Enterprise;
        @TrustZone { zone = Zone::trusted; }
        doc /* The whole fielded capability: everything the program builds, fields and sustains. */
        part sensors : SensorSegment;
        part fireControl : FireControlSegment;
        part interceptors : InterceptorSegment;
        part launchers : LaunchSegment;
        part support : SupportSegment;
        part testAndTraining : TestSegment;

        // segment-to-segment connections, typed by the interface definitions; a zone crossing names the
        // security requirement that covers it (secReq), as the crossings in engineering/Context.sysml do
        interface sensorReports : SensorReportInterface connect producer ::> sensors.surveillanceRadar.reports to consumer ::> fireControl.engagementControlStation.sensorIn;
        interface inflightUplink : InflightUplinkInterface connect transmitter ::> fireControl.communications.uplink to receiver ::> interceptors.round.avionics.uplink { attribute secReq = "secR02"; }
        interface launchControl : LaunchControlInterface connect commander ::> fireControl.engagementControlStation.launchOut to launcher ::> launchers.launcher.launchIn { attribute secReq = "secR03"; }
        interface maintenanceData : MaintenanceDataInterface connect source ::> launchers.launcher.maintenance to sink ::> support.depot.diagnostics.maintenance { attribute secReq = "secR05"; }

        // what each segment satisfies (sysX07 is deliberately left without a satisfy: an orphan)
        satisfy sysF01 by sensors;
        satisfy sysF02 by fireControl;
        satisfy sysF03 by fireControl;
        satisfy sysF04 by fireControl;
        satisfy sysF05 by fireControl;
        satisfy sysF06 by fireControl;
        satisfy sysF07 by interceptors;
        satisfy sysF08 by fireControl;
        satisfy sysF09 by fireControl;
        satisfy sysX01 by sensors;
        satisfy sysX02 by fireControl;
        satisfy sysX03 by launchers;
        satisfy sysX04 by fireControl;
        satisfy sysX05 by fireControl;
        satisfy sysX06 by support;
        satisfy secR01 by fireControl;
        satisfy secR02 by fireControl;
        satisfy secR03 by launchers;
        satisfy secR04 by support;
        satisfy secR05 by support;
        satisfy secR06 by fireControl;
        satisfy secR07 by fireControl;
        satisfy sysL01 by support;
        satisfy sysL02 by support;
        satisfy sysL03 by launchers;
        satisfy sysL04 by support;
        satisfy sysL05 by testAndTraining;
        satisfy sysL06 by support;
    }

    enum def ProgramPhase {
        doc /* Where the program is in its lifecycle; the milestone decisions move it on. */
        enum development;
        enum production;
        enum sustainment;
    }
}
