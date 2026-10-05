// Segment M (Manufacturing & Production): production requirements.
package ProductionRequirements {
    doc /* What Manufacturing shall do to deliver conforming rounds and canisters. */
    private import SecMeta::*;
    @Marking { level = Level::U; }
    requirement prdR01 { attribute doorsId = "HAL-PRD-001"; doc /* Every production lot shall pass lot acceptance before delivery. */ }
    requirement prdR02 { attribute doorsId = "HAL-PRD-002"; doc /* Every round and canister shall be traceable by serial number to its lot. */ }
    requirement prdR03 { attribute doorsId = "HAL-PRD-003"; doc /* Canisters shall be sealed at the factory and opened only at launch. */ }
    requirement prdR04 { attribute doorsId = "HAL-PRD-004"; doc /* The first article of each configuration shall be inspected before rate production. */ }
    requirement prdR05 { attribute doorsId = "HAL-PRD-005"; doc /* The supply chain shall prevent counterfeit parts from entering production. */ }
}
