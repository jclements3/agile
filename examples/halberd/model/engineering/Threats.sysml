// Segment E (Systems Engineering & Integration): the security threat register. One line per threat:
// its STRIDE category and CAPEC id, the asset it attacks and the requirement that mitigates it (an
// empty mitigation is an open threat). The mitigating requirement carries a matching @Mitigates.
package SecurityThreats {
    doc /* Notional cyber threats against Halberd's data and control paths. */
    private import SecMeta::*;
    @Marking { level = Level::U; }

    metadata spoofedTacticalMessage : Threat { asset = "external tactical link"; mitigation = "secR01"; stride = "Spoofing"; capec = "CAPEC-148"; }
    metadata interceptedUplink : Threat { asset = "in-flight uplink"; mitigation = "secR02"; stride = "Information disclosure"; capec = "CAPEC-117"; }
    metadata forgedLaunchCommand : Threat { asset = "launch control interface"; mitigation = "secR03"; stride = "Spoofing"; capec = "CAPEC-151"; }
    metadata tamperedSoftwareBuild : Threat { asset = "fire control software"; mitigation = "secR04"; stride = "Tampering"; capec = "CAPEC-511"; }
    metadata maintenancePivot : Threat { asset = "maintenance network"; mitigation = "secR05"; stride = "Elevation of privilege"; capec = "CAPEC-555"; }
    metadata counterfeitPart : Threat { asset = "supply chain"; mitigation = ""; stride = "Tampering"; capec = "CAPEC-452"; }
    metadata insiderMisuse : Threat { asset = "operator console"; mitigation = ""; stride = "Elevation of privilege"; capec = "CAPEC-122"; }
}
