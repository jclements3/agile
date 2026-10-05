// Segment E (Systems Engineering & Integration): the modeling conventions every segment uses.
package Conventions {
    doc /* Level tags for the part tree (tools/sysml/model.pl checks them); the security metadata is in SecMeta. */
    private import SecMeta::*;
    @Marking { level = Level::U; }

    metadata def L1Enterprise { doc /* The whole enterprise. */ }
    metadata def L2Segment { doc /* A product segment, owned by one organization. */ }
    metadata def L3System { doc /* A deliverable system within a segment. */ }
    metadata def L4Subsystem { doc /* A subsystem: a line-replaceable or separately specified unit. */ }
    metadata def L5Assembly { doc /* An assembly within a subsystem. */ }
    metadata def L6Component { doc /* A component: the lowest level this model describes. */ }
}
