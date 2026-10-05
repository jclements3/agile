package HalberdSystem {
    doc /* Halberd system structure. Notional, for the tree view tests. */
    private import ISQ::*;
    private import SI::*;
    private import HalberdInterfaces::*;

    metadata def L1System;
    metadata def L2Segment;

    part def HalberdSystemDef {
        @L1System;
        doc /* The Halberd weapon system: four segments. */
        attribute defendedRadius : LengthValue = 300 [km];
        part fireControl : FireControlSegment;
        part interceptors : InterceptorSegment[1..*];
        part launchers : LauncherSegment[2..12];
        part support : SupportSegment;
    }

    part def Segment { doc /* Common segment base. */ attribute owner : String; part manager : SegmentManager; }
    part def SegmentManager;

    part def FireControlSegment :> Segment {
        @L2Segment;
        port fromSensors : ~TrackReportPort;
        part software : FireControlSoftware;
        part host : FireControlHost;
        part :>> manager : FireControlManager;   // redefined
    }
    part def FireControlManager :> SegmentManager;
    part def FireControlSoftware {
        part tracker : Tracker;
        part weaponAssigner : WeaponAssigner;
        part 'engagement planner' : EngagementPlanner;
        part dataRecorder : DataRecorder;
    }
    part def Tracker { part filter : IMMFilter; part correlator : Correlator; }
    part def IMMFilter { part models : MotionModel[4]; part mixer : ModelMixer; }
    part def MotionModel; part def ModelMixer; part def Correlator;
    part def WeaponAssigner; part def DataRecorder; part def EngagementPlanner; part def FireControlHost;

    part def InterceptorSegment :> Segment {
        @L2Segment;
        part vehicle : Interceptor;
    }
    part def Interceptor {
        doc /* The interceptor round, rev B. */
        attribute mass : MassValue;
        part booster : Booster;
        part killVehicle : KillVehicle {
            part seeker : Seeker { part :>> optics : WideFieldOptics; }   // nested refinement in place
        }
    }
    part def KillVehicle { part seeker : Seeker; part divert : DivertSystem; }
    part def Seeker { attribute frameRate : FrequencyValue; part optics : Optics; part fpa : FocalPlaneArray; }
    part def Optics; part def WideFieldOptics :> Optics; part def FocalPlaneArray;
    part def DivertSystem; part def Booster; part def Canister;

    part def LauncherSegment :> Segment { part launcher : Launcher; }
    part def Launcher { part loader : Loader; ref part segment : LauncherSegment; }
    part def Loader { part arm : Loader; }                  // recursive on purpose
    part def SupportSegment :> Segment { part depot : Depot; }
    part def Depot;
    part def TestRange { part gateway : RangeGateway; part instrumentation : Instrumentation; }
    part def RangeGateway; part def Instrumentation;
    part def Orphan { part only : Booster; }               // a root with one part (outline rule)
}
