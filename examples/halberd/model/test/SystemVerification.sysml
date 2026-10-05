// Segment T (Test & Evaluation): verification cases for the system requirements.
// sysL06 is deliberately not verified yet (it shows up in trace and in metric G).
package SystemVerification {
    doc /* How each system requirement is verified, and by which method. */
    private import VerificationCases::*;
    private import Enterprise::*;
    private import SystemRequirements::**;
    private import SecMeta::*;
    @Marking { level = Level::CUI; }   // a notional label: the content is notional and unclassified

    verification def VerifySensingChain {
        doc /* Detection, tracking and classification, sensor to console, against simulated and live targets. */
        @VerificationMethod { kind = VerificationMethodKind::test; }
        subject system : HalberdEnterprise;
        objective {
            verify sysF01;
            verify sysF02;
            verify sysF03;
            verify sysX01;
        }
    }
    verification def VerifyEngagementChain {
        doc /* Decide, engage and assess, end to end, in flight test. */
        @VerificationMethod { kind = VerificationMethodKind::test; }
        subject system : HalberdEnterprise;
        objective {
            verify sysF04;
            verify sysF05;
            verify sysF06;
            verify sysF07;
            verify sysF08;
            verify sysX02;
            verify sysX03;
        }
    }
    verification def VerifyEngagementRecording {
        doc /* Inspect the engagement records produced in flight test. */
        @VerificationMethod { kind = VerificationMethodKind::inspect; }
        subject system : HalberdEnterprise;
        objective {
            verify sysF09;
        }
    }
    verification def VerifyExternalExchanges {
        doc /* Demonstrate the external links and the common time reference in a joint exercise. */
        @VerificationMethod { kind = VerificationMethodKind::demo; }
        subject system : HalberdEnterprise;
        objective {
            verify sysX04;
            verify sysX05;
            verify sysX06;
            verify sysX07;
        }
    }
    verification def VerifySecurityControls {
        doc /* Test every security control, including an adversarial assessment. */
        @VerificationMethod { kind = VerificationMethodKind::test; }
        subject system : HalberdEnterprise;
        objective {
            verify secR01;
            verify secR02;
            verify secR03;
            verify secR04;
            verify secR05;
            verify secR06;
            verify secR07;
        }
    }
    verification def VerifySupportability {
        doc /* Demonstrate maintenance, transport and the training mode with a fielding unit. */
        @VerificationMethod { kind = VerificationMethodKind::demo; }
        subject system : HalberdEnterprise;
        objective {
            verify sysL01;
            verify sysL02;
            verify sysL03;
            verify sysL04;
            verify sysL05;
        }
    }
}
