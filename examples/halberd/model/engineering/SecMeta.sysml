// Segment E (Systems Engineering & Integration): the security vocabulary the view tools read
// (tools/sysml/views): markings, trust zones, security requirements, threats and mitigations.
// The marking levels are notional labels: everything in Halberd is notional and unclassified.
library package SecMeta {
    doc /* Security metadata: package markings, trust zones, security requirements, the threat register and its mitigations. */
    private import ScalarValues::*;

    enum def Zone { enum trusted; enum dmz; enum untrusted; }
    enum def Level { enum U; enum CUI; }
    metadata def Marking { doc /* The marking of a package or element (a notional label). */ attribute level : Level; }
    metadata def TrustZone { doc /* The security zone a part sits in; a connection between zones is a boundary crossing. */ attribute zone : Zone; }
    metadata def SecurityRequirement { doc /* A requirement that protects a boundary crossing or mitigates a threat. */ }
    metadata def Threat {
        doc /* A threat: its STRIDE category and CAPEC id, the asset it attacks and the requirement that mitigates it (empty: none yet). */
        attribute stride : String;
        attribute capec : String;
        attribute asset : String;
        attribute mitigation : String;
    }
    metadata def Mitigates { doc /* On a requirement: the threat it mitigates. */ attribute threat : String; }
    metadata def RiskAcceptance { doc /* An accepted open threat: who accepted it and until when. */ attribute threat : String; attribute approver : String; attribute expires : String; }

    @Marking { level = Level::U; }
}
