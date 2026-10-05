package HalberdInterceptorSatisfaction {
    doc /* Which configured element satisfies the interceptor specification. */
    private import HalberdInterceptorSpecification::*;

    part blockOne : Interceptor;
    part killVehicle : Interceptor;
    satisfy interceptorSpec.massWithinAllocation by blockOne;
    satisfy interceptorSpec.seekerFrameRate by blockOne;
    satisfy interceptorSpec.divertCapability by killVehicle;
    // HAL-INT-004 deliberately unsatisfied
}
