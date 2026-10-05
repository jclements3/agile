// Segment B (Battle Management & Fire Control): the fire control software, built by an agile
// team-of-teams. Structure only.
package FireControlSoftwareDefs {
    doc /* The software configuration items of fire control. */
    private import Conventions::*;
    private import FireControlRequirements::*;

    part def FireControlSoftware {
        @L3System;
        doc /* The fire control software: one configuration item per kill-chain responsibility. */
        part trackManager : TrackManager;
        part threatEvaluator : ThreatEvaluator;
        part weaponScheduler : WeaponScheduler;
        part engagementMonitor : EngagementMonitor;

        satisfy fcR01 by trackManager;
        satisfy fcR02 by threatEvaluator;
        satisfy fcR03 by weaponScheduler;
        satisfy fcR05 by engagementMonitor;
        satisfy fcR07 by trackManager;
    }
    part def TrackManager { @L4Subsystem; doc /* Keeps the single integrated picture. */ }
    part def ThreatEvaluator { @L4Subsystem; doc /* Classifies and ranks threats. */ }
    part def WeaponScheduler { @L4Subsystem; doc /* Pairs interceptors with threats and schedules launches. */ }
    part def EngagementMonitor { @L4Subsystem; doc /* Watches each engagement through to its assessment. */ }
}
