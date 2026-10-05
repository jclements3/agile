package HalberdSecurityVerification {
    doc /* Verification of the security requirements. */
    private import SecMeta::*;
    private import HalberdSecurityRequirements::*;
    @Marking { level = Level::U; }
    verification def FrameAuthenticationTest {
        objective { verify frameAuthentication; }
    }
}
