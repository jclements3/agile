// Segment L (Logistics & Sustainment): the support segment -- depot and field support. Structure only.
package Support {
    doc /* What keeps fielded Halberd units ready. */
    private import Conventions::*;
    private import InterfaceDefinitions::*;
    private import SustainmentRequirements::*;

    part def SupportSegment {
        @L2Segment;
        doc /* Depot and field support for every fielded unit. */
        part depot : MaintenanceDepot;
        part fieldKit : FieldSupportKit;

        satisfy susR01 by depot;
        satisfy susR02 by fieldKit;
        satisfy susR03 by depot;
        satisfy susR04 by depot;
    }
    part def MaintenanceDepot {
        @L3System;
        doc /* Repairs line-replaceable units and stores spare rounds. */
        part diagnostics : DiagnosticsWorkstation;
        part storage : SpareRoundStorage;
    }
    part def FieldSupportKit {
        @L3System;
        doc /* What maintainers carry to a fielded unit. */
        part testSet : RoundTestSet;
        part tools : ToolKit;
    }
    part def DiagnosticsWorkstation { @L4Subsystem; doc /* Reads health data and isolates faults. */ port maintenance : ~MaintenanceDataPort; }
    part def SpareRoundStorage { @L4Subsystem; doc /* Monitored storage for spare rounds in their canisters. */ }
    part def RoundTestSet { @L4Subsystem; doc /* Checks a round in its canister. */ }
    part def ToolKit { @L4Subsystem; doc /* Hand tools and handling equipment. */ }
    item def HealthReport { doc /* Health and fault data from a launcher or a round. */ }
}
