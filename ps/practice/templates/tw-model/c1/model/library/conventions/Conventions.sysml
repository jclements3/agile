// Government-owned (model/library/conventions): the metadata the team tags the model with, in one place,
// reviewed by merge request. The level tags below name the levels of the part tree, top first (sysml.conf
// level_tags lists the same names). The port adds here whatever else the v1 profile had.
package Conventions {
    doc /* Metadata definitions used across the model. */
    metadata def L1Network { doc /* Level 1 of the part tree. */ }
    metadata def L2Segment { doc /* Level 2 of the part tree. */ }
    metadata def L3Station { doc /* Level 3 of the part tree. */ }
    metadata def L4Subsystem { doc /* Level 4 of the part tree. */ }
    metadata def L5Assembly { doc /* Level 5 of the part tree. */ }
    metadata def L6Component { doc /* Level 6 of the part tree. */ }
}
