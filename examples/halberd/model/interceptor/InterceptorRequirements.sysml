// Segment V (Interceptor Development): interceptor segment requirements.
package InterceptorRequirements {
    doc /* The interceptor segment specification. */
    private import SecMeta::*;
    @Marking { level = Level::U; }
    requirement intR01 { attribute doorsId = "HAL-INT-001"; doc /* The booster shall separate cleanly from the kill vehicle. */ }
    requirement intR02 { attribute doorsId = "HAL-INT-002"; doc /* The kill vehicle shall divert to correct its course in the endgame. */ }
    requirement intR03 { attribute doorsId = "HAL-INT-003"; doc /* The seeker shall take over from in-flight updates for terminal homing. */ }
    requirement intR04 { attribute doorsId = "HAL-INT-004"; doc /* The round shall accept in-flight updates until seeker handover. */ }
    requirement intR05 { attribute doorsId = "HAL-INT-005"; doc /* The round shall make itself safe when guidance is lost. */ }
    requirement intR06 { attribute doorsId = "HAL-INT-006"; doc /* The round shall meet insensitive-munitions policy. */ }
    requirement intR07 { attribute doorsId = "HAL-INT-007"; doc /* A test round shall telemeter its flight to the range. */ }
    requirement intR08 { attribute doorsId = "HAL-INT-008"; doc /* A round shall be stored in its canister without periodic maintenance. */ }
}
