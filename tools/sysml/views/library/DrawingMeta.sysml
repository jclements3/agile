library package DrawingMeta {
    doc /* Title-block data for drawing plates generated from views (sysml-plates.pl). */
    private import ScalarValues::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }
    metadata def Drawing {
        doc /* Overrides for a plate's title block. Every attribute is optional. */
        attribute number : String;
        attribute revision : String;
        attribute size : String;
        attribute status : String;
        attribute drawnBy : String;
        attribute approvedBy : String;
        attribute owner : String;
    }
}
