package IAMDSketch {
    doc /* Enterprise-level wiring of a notional defense enterprise (shapes only). */
    private import SecMeta::*;
    @Marking { level = Level::U; }
    port def TrackReportPort;
    port def FireControlPort;
    interface def SensorReportingInterface { end sensor : TrackReportPort; end c2 : ~TrackReportPort; }
    interface def FireControlInterface { end c2 : FireControlPort; end fireUnit : ~FireControlPort; }
    part def BattleManagerDef { port sensorReports : ~TrackReportPort; port kineticFireControl : FireControlPort; port deFireControl : FireControlPort; }
    part def SensorSegmentDef { port reports : TrackReportPort; }
    part def KineticSegmentDef { port fireControl : ~FireControlPort; }
    part def DirectedEnergySegmentDef { port fireControl : ~FireControlPort; }
    part def CommunicationsSegmentDef;
    part def SustainmentSegmentDef;
    part def IAMDEnterpriseDef {
        part battleMgr : BattleManagerDef;
        part sensors : SensorSegmentDef;
        part kinetic : KineticSegmentDef;
        part directedEnergy : DirectedEnergySegmentDef;
        part communications : CommunicationsSegmentDef;
        part sustainment : SustainmentSegmentDef;
        interface sensorToC2 : SensorReportingInterface
            connect sensor ::> sensors.reports to c2 ::> battleMgr.sensorReports;
        interface c2ToKinetic : FireControlInterface
            connect c2 ::> battleMgr.kineticFireControl to fireUnit ::> kinetic.fireControl;
        interface c2ToDirectedEnergy : FireControlInterface
            connect c2 ::> battleMgr.deFireControl to fireUnit ::> directedEnergy.fireControl;
    }
}
