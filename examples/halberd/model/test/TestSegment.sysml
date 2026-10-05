// Segment T (Test & Evaluation): the test and training segment. Structure only.
package TestAndTraining {
    doc /* Range instrumentation for flight tests and the crew trainer. */
    private import Conventions::*;
    private import TestRequirements::*;

    part def TestSegment {
        @L2Segment;
        doc /* Everything used to test Halberd and to train its crews. */
        part rangeInstrumentation : RangeInstrumentation;
        part trainer : TrainingSimulator;

        satisfy tstR01 by rangeInstrumentation;
        satisfy tstR02 by rangeInstrumentation;
        satisfy tstR03 by trainer;
    }
    part def RangeInstrumentation {
        @L3System;
        doc /* Records what happens in a flight test. */
        part telemetryStation : TelemetryStation;
        part opticalTracker : OpticalTracker;
    }
    part def TrainingSimulator {
        @L3System;
        doc /* Trains crews on the real consoles with simulated threats. */
        part instructorStation : InstructorStation;
        part scenarioGenerator : ScenarioGenerator;
    }
    part def TelemetryStation { @L4Subsystem; doc /* Receives and records test-round telemetry. */ }
    part def OpticalTracker { @L4Subsystem; doc /* Films the flight from the ground. */ }
    part def InstructorStation { @L4Subsystem; doc /* Where the instructor runs a training scenario. */ }
    part def ScenarioGenerator { @L4Subsystem; doc /* Generates simulated threats for training. */ }
}
