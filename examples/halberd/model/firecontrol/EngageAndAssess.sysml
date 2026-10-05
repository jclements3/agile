// Segment B (Battle Management & Fire Control): the functions of engage and assess.
package EngageAndAssess {
    doc /* From the engagement plan to the engagement record. */
    private import KillChainItems::**;

    action def LaunchInterceptor { doc /* Launch the interceptor the plan calls for. */ in plan : EngagementPlan; out result : LaunchEvent; }
    action def GuideInterceptor {
        doc /* Keep the interceptor on course with track updates until it homes on its own. */
        in launchEvent : LaunchEvent;
        in tracks : TrackSet;
        out result : EngagementEvents = home.result;
        action uplink : UplinkTrackUpdates { in launchEvent = GuideInterceptor::launchEvent; in tracks = GuideInterceptor::tracks; }
        action home : HomeOnTarget { in updates = uplink.result; }
    }
    action def UplinkTrackUpdates { doc /* Send track updates to the interceptor in flight. */ in launchEvent : LaunchEvent; in tracks : TrackSet; out result : InflightUpdates; }
    action def HomeOnTarget { doc /* The interceptor's own terminal homing. */ in updates : InflightUpdates; out result : EngagementEvents; }
    action def JudgeEngagement { doc /* Decide whether the threat was defeated. */ in events : EngagementEvents; out result : KillAssessment; }
    action def ReportOutcome { doc /* Record the engagement and report it. */ in assessment : KillAssessment; in plan : EngagementPlan; out result : EngagementRecord; }
}
