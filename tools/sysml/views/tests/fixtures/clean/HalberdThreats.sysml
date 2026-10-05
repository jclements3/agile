package HalberdThreats {
    doc /* Threats to the flight-test telemetry path. Notional. */
    private import SecMeta::*;
    @Marking { level = Level::U; }

    occurrence def InjectedTelemetry {
        @Threat { stride = "Spoofing"; capec = "CAPEC-151"; }
        doc /* A device on the range network sends frames that appear to come from the build. */
    }
    occurrence def ModifiedTelemetry {
        @Threat { stride = "Tampering"; capec = "CAPEC-94"; }
        doc /* Frames are altered between the gateway and the range recorders. */
    }
    occurrence def FloodedGateway {
        @Threat { stride = "Denial of service"; capec = "CAPEC-125"; }
        @RiskAcceptance { threat = "FloodedGateway"; approver = "jdoe"; expires = "2027-03-31"; }
        doc /* The range side floods the gateway so program telemetry is lost. */
    }
}
