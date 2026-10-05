// Segment V (Interceptor Development): the interceptor segment and the round. Structure only --
// no design content.
package Interceptor {
    doc /* The interceptor round and its instrumented test variant. */
    private import Conventions::*;
    private import InterfaceDefinitions::*;
    private import InterceptorComponents::*;
    private import InterceptorRequirements::*;

    part def InterceptorSegment {
        @L2Segment;
        doc /* Every interceptor round the program delivers. */
        part round : InterceptorRound;
        part testRound : InstrumentedTestRound;
    }
    part def InterceptorRound {
        @L3System;
        doc /* A tactical round: booster, kill vehicle and avionics. */
        part booster : BoosterStage;
        part killVehicle : KillVehicle;
        part avionics : AvionicsSection;

        satisfy intR01 by booster;
        satisfy intR02 by killVehicle;
        satisfy intR03 by killVehicle;
        satisfy intR04 by avionics;
        satisfy intR05 by avionics;
        satisfy intR06 by booster;
        satisfy intR08 by booster;
    }
    part def InstrumentedTestRound :> InterceptorRound {
        @L3System;
        doc /* A flight-test round: a tactical round plus a telemetry kit. */
        part telemetry : TelemetryKit;

        satisfy intR07 by telemetry;
    }
    part def BoosterStage {
        @L4Subsystem;
        doc /* Carries the kill vehicle up and out. */
        part motor : RocketMotor;
        part thrustVectorControl : ThrustVectorControl;
    }
    part def KillVehicle {
        @L4Subsystem;
        doc /* Finds the threat and steers into it. */
        part seeker : Seeker;
        part divert : DivertSystem;
        part guidanceProcessor : GuidanceProcessor;
    }
    part def AvionicsSection {
        @L4Subsystem;
        doc /* Flight computer, uplink receiver and power. */
        part flightComputer : FlightComputer;
        part uplinkReceiver : DataLinkTransceiver;
        part battery : ThermalBattery;
        port uplink : ~UplinkPort;
    }
    part def TelemetryKit { @L4Subsystem; doc /* Flight-test instrumentation: telemetry and flight termination. */ }
}
