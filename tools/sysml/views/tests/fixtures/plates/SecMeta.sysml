library package SecMeta {
    doc /* Security vocabulary. */
    private import ScalarValues::*;
    enum def Zone  { enum trusted; enum dmz; enum untrusted; }
    enum def Level { enum U; enum CUI; enum ITAR; }
    metadata def Marking { attribute level : Level; }
    metadata def TrustZone { attribute zone : Zone; }
    metadata def SecurityRequirement;
    @Marking { level = Level::U; }
}
