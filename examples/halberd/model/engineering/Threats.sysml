// Segment E (Systems Engineering & Integration): the security threat register. Each threat names
// the asset it attacks and the requirement that mitigates it; an empty mitigation is an open threat.
package SecurityThreats {
    doc /* Notional cyber threats against Halberd's data and control paths. */
    private import Conventions::*;

    metadata spoofedTacticalMessage : Threat { asset = "external tactical link"; mitigation = "secR01"; }
    metadata interceptedUplink : Threat { asset = "in-flight uplink"; mitigation = "secR02"; }
    metadata forgedLaunchCommand : Threat { asset = "launch control interface"; mitigation = "secR03"; }
    metadata tamperedSoftwareBuild : Threat { asset = "fire control software"; mitigation = "secR04"; }
    metadata maintenancePivot : Threat { asset = "maintenance network"; mitigation = "secR05"; }
    metadata counterfeitPart : Threat { asset = "supply chain"; mitigation = ""; }
    metadata insiderMisuse : Threat { asset = "operator console"; mitigation = ""; }
}
