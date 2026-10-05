package HalberdInterceptorSpecification {
    doc /* Interceptor segment specification (V). Notional; values are placeholders. */
    private import ISQ::*;
    private import SI::*;

    part def Interceptor {
        doc /* The Halberd interceptor, as the subject of its specification. */
        attribute mass : MassValue;
        attribute allocatedMass : MassValue;
        attribute seekerFrameTime : DurationValue;
        attribute requiredFrameTime : DurationValue;
    }

    requirement def InterceptorRequirement {
        doc /* A requirement whose subject is the interceptor. */
        subject interceptor : Interceptor;
    }

    requirement <'HAL-INT'> interceptorSpec : InterceptorRequirement {
        doc /* Interceptor specification. */
        requirement <'HAL-INT-001'> massWithinAllocation : InterceptorRequirement {
            doc /* The interceptor mass shall not exceed its allocated mass. */
            require constraint { interceptor.mass <= interceptor.allocatedMass }
        }
        requirement <'HAL-INT-002'> seekerFrameRate : InterceptorRequirement {
            doc /* The seeker frame time shall not exceed the frame time the
                 * fire control segment requires (ICD-allocated). */
            require constraint { interceptor.seekerFrameTime <= interceptor.requiredFrameTime }
        }
        requirement <'HAL-INT-003'> divertCapability : InterceptorRequirement {
            doc /* The kill vehicle shall provide the divert velocity allocated by the engagement analysis. */
        }
        requirement <'HAL-INT-004'> storageLife : InterceptorRequirement {
            doc /* The interceptor shall meet its reliability allocation after the specified storage period. */
        }
    }
}
