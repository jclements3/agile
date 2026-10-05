// Segment L (Logistics & Sustainment): sustainment requirements.
package SustainmentRequirements {
    doc /* What sustainment shall provide once units are fielded. */
    private import SecMeta::*;
    @Marking { level = Level::U; }
    requirement susR01 { attribute doorsId = "HAL-SUS-001"; doc /* The depot shall repair every line-replaceable unit. */ }
    requirement susR02 { attribute doorsId = "HAL-SUS-002"; doc /* The field kit shall isolate a fault to one line-replaceable unit. */ }
    requirement susR03 { attribute doorsId = "HAL-SUS-003"; doc /* Spare rounds shall be health-monitored in storage. */ }
    requirement susR04 { attribute doorsId = "HAL-SUS-004"; doc /* Fielded software shall receive maintenance releases. */ }
    requirement susR05 { attribute doorsId = "HAL-SUS-005"; doc /* Field reliability data shall be collected and returned to engineering. */ }
}
