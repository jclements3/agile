package HalberdSecurityRequirements {
    doc /* Security requirements on the flight-test configuration. Notional. */
    private import SecMeta::*;
    private import HalberdFlightTest::*;
    @Marking { level = Level::U; }

    requirement <'HAL-SEC-001'> frameAuthentication {
        @SecurityRequirement;
        doc /* Every telemetry frame shall carry an authentication tag checked by the gateway. */
        subject cfg : FlightTestConfiguration;
    }
    requirement <'HAL-SEC-002'> benchIsolation {
        @SecurityRequirement;
        doc /* The bench shall be isolated from range networks. */
        subject cfg : ShortcutConfiguration;
    }
    part flightTest : FlightTestConfiguration;
    satisfy frameAuthentication by flightTest;
    // HAL-SEC-002 not yet satisfied
}
