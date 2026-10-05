// Segment T (Test & Evaluation): verification cases for the segment requirements.
// fcR08, intR06 and tstR03 are deliberately not verified yet (trace and metric G show them).
package SegmentVerification {
    doc /* How each segment requirement is verified, and by which method. */
    private import VerificationCases::*;
    private import FireControl::*;
    private import Interceptor::*;
    private import Launch::*;
    private import Support::*;
    private import TestAndTraining::*;
    private import FireControlRequirements::*;
    private import InterceptorRequirements::*;
    private import ProductionRequirements::*;
    private import SustainmentRequirements::*;
    private import TestRequirements::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    verification def VerifyFireControlSoftware {
        doc /* Qualification test of each fire control software build. */
        @VerificationMethod { kind = VerificationMethodKind::test; }
        subject segment : FireControlSegment;
        objective {
            verify fcR01;
            verify fcR02;
            verify fcR03;
            verify fcR04;
            verify fcR05;
            verify fcR06;
            verify fcR07;
        }
    }
    verification def VerifyInterceptorFlight {
        doc /* Flight test of instrumented test rounds. */
        @VerificationMethod { kind = VerificationMethodKind::test; }
        subject round : InstrumentedTestRound;
        objective {
            verify intR01;
            verify intR02;
            verify intR03;
            verify intR04;
            verify intR05;
            verify intR07;
        }
    }
    verification def VerifyInterceptorStorage {
        doc /* Inspect rounds drawn from canister storage. */
        @VerificationMethod { kind = VerificationMethodKind::inspect; }
        subject round : InterceptorRound;
        objective {
            verify intR08;
        }
    }
    verification def VerifyProductionControls {
        doc /* Inspect lot acceptance, traceability, sealing, first articles and parts control. */
        @VerificationMethod { kind = VerificationMethodKind::inspect; }
        subject segment : LaunchSegment;
        objective {
            verify prdR01;
            verify prdR02;
            verify prdR03;
            verify prdR04;
            verify prdR05;
        }
    }
    verification def VerifySustainment {
        doc /* Demonstrate depot repair, field fault isolation and reliability reporting. */
        @VerificationMethod { kind = VerificationMethodKind::demo; }
        subject segment : SupportSegment;
        objective {
            verify susR01;
            verify susR02;
            verify susR03;
            verify susR04;
            verify susR05;
        }
    }
    verification def VerifyTestInfrastructure {
        doc /* Demonstrate the range instrumentation before the first flight test. */
        @VerificationMethod { kind = VerificationMethodKind::demo; }
        subject segment : TestSegment;
        objective {
            verify tstR01;
            verify tstR02;
        }
    }
}
