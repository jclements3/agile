package HalberdThreats {
    doc /* Threat set. One element is ITAR inside a CUI package. */
    private import SecMeta::*;
    private import HalberdFireControl::*;
    @Marking { level = Level::CUI; }
    part def ReplayThreat { part target : FireControlSegment; }
    part def JammerModel {
        @Marking { level = Level::ITAR; }
        doc /* Jammer technique parameters. */
    }
}
