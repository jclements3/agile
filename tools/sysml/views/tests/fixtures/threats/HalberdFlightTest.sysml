package HalberdFlightTest {
    doc /* Notional: the fire-control build under test, joined to the test range for a flight test. */
    private import ScalarValues::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    item def TelemetryFrame {
        attribute sequence : Integer;
        attribute authTag : String;
    }
    port def TelemetryPort { out item frames : TelemetryFrame; }

    part def FireControlBuild {
        @TrustZone { zone = Zone::trusted; }
        port telemetry : TelemetryPort;
    }
    part def RangeGateway {
        @TrustZone { zone = Zone::dmz; }
        port fromProgram : ~TelemetryPort;
        port toRange : TelemetryPort;
    }
    part def RangeInstrumentation {
        @TrustZone { zone = Zone::untrusted; }
        port feed : ~TelemetryPort;
    }
    interface def TelemetryLink {
        end src : TelemetryPort;
        end dst : ~TelemetryPort;
    }
    part def FlightTestConfiguration {
        part fireControl : FireControlBuild;
        part gateway : RangeGateway;
        part range : RangeInstrumentation;
        interface programToGateway : TelemetryLink
            connect src ::> fireControl.telemetry to dst ::> gateway.fromProgram;
        interface gatewayToRange : TelemetryLink
            connect src ::> gateway.toRange to dst ::> range.feed;
    }

    /* A second configuration: the build talks to the range directly, and nothing covers it. */
    part def ShortcutConfiguration {
        doc /* Bench setup that bypasses the gateway. */
        port maintenance : TelemetryPort;
        part fireControl : FireControlBuild;
        part range : RangeInstrumentation;
        part recorder : Recorder;
        connect fireControl.telemetry to range.feed;
        flow of TelemetryFrame from fireControl.telemetry to recorder.input;
        connect maintenance to fireControl.telemetry;
    }
    part def Recorder { port input : ~TelemetryPort; }
}
