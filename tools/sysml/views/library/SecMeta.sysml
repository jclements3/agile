library package SecMeta {
    doc /* Security vocabulary. */
    private import ScalarValues::*;
    enum def Zone  { enum trusted; enum dmz; enum untrusted; }
    enum def Level { enum U; enum CUI; enum ITAR; }
    metadata def Marking { attribute level : Level; }
    metadata def TrustZone { attribute zone : Zone; }
    metadata def SecurityRequirement;
    metadata def Threat    { attribute stride : String; attribute capec : String; }
    metadata def Mitigates { attribute threat : String; }
    metadata def RiskAcceptance { attribute threat : String; attribute approver : String; attribute expires : String; }
    @Marking { level = Level::U; }
}
