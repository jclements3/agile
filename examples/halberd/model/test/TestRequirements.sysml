// Segment T (Test & Evaluation): requirements on the test and training equipment.
package TestRequirements {
    doc /* What the test and training segment shall do. */
    private import SecMeta::*;
    @Marking { level = Level::U; }
    requirement tstR01 { attribute doorsId = "HAL-TST-001"; doc /* Range instrumentation shall record every flight test from launch to intercept. */ }
    requirement tstR02 { attribute doorsId = "HAL-TST-002"; doc /* The telemetry station shall receive and archive test-round telemetry. */ }
    requirement tstR03 { attribute doorsId = "HAL-TST-003"; doc /* The trainer shall inject simulated threats into the operator consoles. */ }
}
