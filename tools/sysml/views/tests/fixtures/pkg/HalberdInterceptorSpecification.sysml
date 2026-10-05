package HalberdInterceptorSpecification {
    doc /* U specification that wrongly pulls in ITAR seeker data. */
    private import SecMeta::*;
    private import HalberdSeekerPerformance::*;
    @Marking { level = Level::U; }
    part def Interceptor { part seeker : SeekerProfile; }
}
