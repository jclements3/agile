package HalberdInterceptorVerification {
    doc /* Verification cases for the interceptor specification. */
    private import VerificationCases::*;
    private import HalberdInterceptorSpecification::*;

    verification def MassPropertiesInspection {
        subject interceptor : Interceptor;
        objective {
            verify interceptorSpec.massWithinAllocation;
        }
    }
    verification def SeekerFrameTimeTest {
        subject interceptor : Interceptor;
        objective {
            verify interceptorSpec.seekerFrameRate;
        }
    }
    verification def InterceptorQualificationTest {
        /* a group-level verify: covers every leaf below it */
        objective { verify interceptorSpec.storageLife; }
    }
    verification def HotLaunchTest {
        objective { verify interceptorSpec.hotLaunch; }
    }
}
