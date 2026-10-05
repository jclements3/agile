// Segment T (Test & Evaluation): operational acceptance -- the stakeholder needs, verified with users.
package AcceptanceTests {
    doc /* Operational test and evaluation of the stakeholder needs. */
    private import VerificationCases::*;
    private import SystemContext::*;
    private import StakeholderNeeds::*;

    verification def AcceptOperationalCapability {
        doc /* Operational test: a crew defends an area in a joint exercise. */
        @VerificationMethod { kind = VerificationMethodKind::test; }
        subject context : HalberdContext;
        objective {
            verify stk01;
            verify stk02;
            verify stk03;
            verify stk04;
        }
    }
    verification def AcceptLifecycleSupport {
        doc /* A fielding unit moves, maintains and trains on Halberd. */
        @VerificationMethod { kind = VerificationMethodKind::demo; }
        subject context : HalberdContext;
        objective {
            verify stk05;
            verify stk06;
            verify stk08;
        }
    }
    verification def AcceptCyberResilience {
        doc /* Adversarial cyber assessment during operational test. */
        @VerificationMethod { kind = VerificationMethodKind::test; }
        subject context : HalberdContext;
        objective {
            verify stk07;
        }
    }
}
