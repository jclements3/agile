// Segment B (Battle Management & Fire Control): fire control segment requirements.
package FireControlRequirements {
    doc /* The fire control segment specification. */
    private import SecMeta::*;
    @Marking { level = Level::U; }
    requirement fcR01 { attribute doorsId = "HAL-BMF-001"; doc /* Fire control shall keep one integrated picture from all sensor reports. */ }
    requirement fcR02 { attribute doorsId = "HAL-BMF-002"; doc /* Threat evaluation shall apply the engagement doctrine in force. */ }
    requirement fcR03 { attribute doorsId = "HAL-BMF-003"; doc /* The weapon schedule shall never assign one interceptor to two threats. */ }
    requirement fcR04 { attribute doorsId = "HAL-BMF-004"; doc /* The console shall show the status of every engagement in progress. */ }
    requirement fcR05 { attribute doorsId = "HAL-BMF-005"; doc /* Fire control shall recommend a re-engagement when an assessment shows a miss. */ }
    requirement fcR06 { attribute doorsId = "HAL-BMF-006"; doc /* The station shall continue the kill chain after a single processor failure. */ }
    requirement fcR07 { attribute doorsId = "HAL-BMF-007"; doc /* Every software increment shall be built and tested by the integration pipeline. */ }
    requirement fcR08 { attribute doorsId = "HAL-BMF-008"; doc /* The communications node shall carry two external tactical links at once. */ }
}
