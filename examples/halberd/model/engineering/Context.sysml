// Segment E (Systems Engineering & Integration): the system context -- Halberd among the things
// outside it -- with the allocation of the kill chain to parts and the security-zone crossings.
package SystemContext {
    doc /* Halberd in its operational context. */
    private import Enterprise::*;
    private import InterfaceDefinitions::*;
    private import KillChain::*;
    private import StakeholderNeeds::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    part def HalberdContext {
        doc /* The system of interest and the external actors it exchanges data with. */
        part halberd : HalberdEnterprise;
        part threat : BallisticThreat;
        part command : HigherEchelonCommand;
        part neighbor : AdjacentDefenseUnit;

        perform action defend : DefendAgainstThreat;

        // the kill chain allocated to the parts that perform it (IDEF0 mechanisms)
        allocate defend to halberd;
        allocate defend.detect to halberd.sensors;
        allocate defend.detect.condition to halberd.sensors.surveillanceRadar;
        allocate defend.track to halberd.fireControl.fireControlSoftware;
        allocate defend.identify to halberd.fireControl.fireControlSoftware;
        allocate defend.decision to halberd.fireControl.engagementControlStation;
        allocate defend.engage to halberd.interceptors;
        allocate defend.engage.launch to halberd.launchers;
        allocate defend.assess to halberd.fireControl;

        // boundary crossings: one line each, with the zone at each end and the security requirement
        // that covers the crossing (empty: not yet covered)
        interface ifcSensorReports { end ::> halberd.sensors.surveillanceRadar.reports; end ::> halberd.fireControl.engagementControlStation.sensorIn; attribute fromZone = "trusted"; attribute toZone = "trusted"; attribute secReq = ""; }
        interface ifcInflightUplink { end ::> halberd.fireControl.communications.uplink; end ::> halberd.interceptors.round.avionics.uplink; attribute fromZone = "trusted"; attribute toZone = "untrusted"; attribute secReq = "secR02"; }
        interface ifcLaunchControl { end ::> halberd.fireControl.engagementControlStation.launchOut; end ::> halberd.launchers.launcher.launchIn; attribute fromZone = "trusted"; attribute toZone = "dmz"; attribute secReq = "secR03"; }
        interface ifcHigherCommand { end ::> halberd.fireControl.communications.tacticalLink; end ::> command.tacticalLink; attribute fromZone = "trusted"; attribute toZone = "untrusted"; attribute secReq = "secR01"; }
        interface ifcAdjacentUnit { end ::> halberd.fireControl.communications.tacticalLink; end ::> neighbor.tacticalLink; attribute fromZone = "trusted"; attribute toZone = "untrusted"; attribute secReq = ""; }
        interface ifcMaintenanceData { end ::> halberd.launchers.launcher.maintenance; end ::> halberd.support.depot.diagnostics.maintenance; attribute fromZone = "dmz"; attribute toZone = "trusted"; attribute secReq = "secR05"; }

        // the stakeholder needs, met by the enterprise as a whole
        satisfy stk01 by halberd;
        satisfy stk02 by halberd;
        satisfy stk03 by halberd;
        satisfy stk04 by halberd;
        satisfy stk05 by halberd;
        satisfy stk06 by halberd;
        satisfy stk07 by halberd;
        satisfy stk08 by halberd;
    }

    part def BallisticThreat { @TrustZone { zone = Zone::untrusted; } doc /* The object Halberd defends against. Notional: no characteristics are modeled. */ }
    part def HigherEchelonCommand { @TrustZone { zone = Zone::untrusted; } doc /* The command that tasks Halberd and receives its reports. */ port tacticalLink : ~TacticalLinkPort; }
    part def AdjacentDefenseUnit { @TrustZone { zone = Zone::untrusted; } doc /* A neighbouring defense unit that shares its air picture. */ port tacticalLink : ~TacticalLinkPort; }
}
