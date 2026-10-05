package HalberdSecurityRequirements {
    doc /* Security requirements on the flight-test configuration. Notional. */
    private import SecMeta::*;
    private import HalberdFlightTest::*;
    @Marking { level = Level::U; }

    requirement <'HAL-SEC-001'> frameAuthentication {
        @SecurityRequirement;
        @Mitigates { threat = "InjectedTelemetry"; }
        @Mitigates { threat = "ModifiedTelemetry"; }
        doc /* Every telemetry frame shall carry an authentication tag checked by the gateway. */
        subject cfg : FlightTestConfiguration;
    }
    requirement <'HAL-SEC-003'> commandFreshness {
        @SecurityRequirement;
        @Mitigates { threat = "ReplayedCommands"; }
        @Mitigates { threat = "GhostThreat"; }
        doc /* Uplink commands shall carry a sequence number checked for freshness. */
        subject cfg : FlightTestConfiguration;
    }
    part flightTest : FlightTestConfiguration;
    satisfy frameAuthentication by flightTest;
    satisfy commandFreshness by flightTest;
}
