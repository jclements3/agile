package HalberdInterceptorSatisfaction {
    doc /* Which configured element satisfies the interceptor specification. */
    private import HalberdInterceptorSpecification::*;

    part blockOne : Interceptor;
    part canisterRound : Interceptor;
    satisfy interceptorSpec.massWithinAllocation by blockOne;
    satisfy interceptorSpec.seekerFrameRate by blockOne;
    satisfy interceptorSpec.storageLife by canisterRound;
}
