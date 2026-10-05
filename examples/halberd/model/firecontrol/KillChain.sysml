// Segment B (Battle Management & Fire Control): the kill chain as functions (the verb tree).
// Each action takes its inputs and hands on one result (out result); a child's result is
// child.result. tools/sysml/model.pl idef0 draws this tree as IDEF0 plates, one model per step.
package KillChain {
    doc /* Detect, track, identify, decide, engage, assess. */
    private import KillChainItems::**;
    private import SenseAndDecide::*;
    private import EngageAndAssess::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    action def DefendAgainstThreat {
        doc /* Defend the assigned area against one threat, from first detection to the engagement record. */
        in inputs : MissionInputs;
        out result : EngagementRecord = assess.result;
        action detect : Detect { in returns = DefendAgainstThreat::inputs.sensorReturns; in tasking = DefendAgainstThreat::inputs.tasking; }
        action track : Track { in detections = detect.result; }
        action identify : Identify { in tracks = track.result; in catalog = DefendAgainstThreat::inputs.threatLibrary; }
        action decision : Decide { in threats = identify.result; in doctrine = DefendAgainstThreat::inputs.doctrine; in authority = DefendAgainstThreat::inputs.authority; }
        action engage : Engage { in plan = decision.result; in tracks = track.result; }
        action assess : Assess { in events = engage.result; in plan = decision.result; }
    }

    action def Detect {
        doc /* Turn sensor returns into declared detections, looking where the sensors are tasked. */
        in returns : SensorReturns;
        in tasking : SensorTasking;
        out result : DetectionSet = declare.result;
        action condition : ConditionSignals { in returns = Detect::returns; }
        action declare : DeclareDetections { in signals = condition.result; in tasking = Detect::tasking; }
    }

    action def Track {
        doc /* Associate detections with tracks and keep every track up to date. */
        in detections : DetectionSet;
        out result : TrackSet = maintain.result;
        action associate : AssociateDetections { in detections = Track::detections; }
        action maintain : MaintainTracks { in associations = associate.result; }
    }

    action def Identify {
        doc /* Decide what each track is, against the threat library. */
        in tracks : TrackSet;
        in catalog : ThreatLibrary;
        out result : ClassifiedTrackSet = classify.result;
        action characterize : CharacterizeTracks { in tracks = Identify::tracks; }
        action classify : ClassifyThreats { in features = characterize.result; in catalog = Identify::catalog; }
    }

    action def Decide {
        doc /* Rank the threats, pair interceptors with them, and schedule authorized launches. */
        in threats : ClassifiedTrackSet;
        in doctrine : EngagementDoctrine;
        in authority : FireAuthorization;
        out result : EngagementPlan = schedule.result;
        action evaluate : EvaluateThreats { in threats = Decide::threats; in doctrine = Decide::doctrine; }
        action pair : PairWeapons { in priorities = evaluate.result; }
        action schedule : ScheduleEngagements { in pairings = pair.result; in authority = Decide::authority; }
    }

    action def Engage {
        doc /* Launch the scheduled interceptors and guide them to their threats. */
        in plan : EngagementPlan;
        in tracks : TrackSet;
        out result : EngagementEvents = guide.result;
        action launch : LaunchInterceptor { in plan = Engage::plan; }
        action guide : GuideInterceptor { in launchEvent = launch.result; in tracks = Engage::tracks; }
    }

    action def Assess {
        doc /* Judge each engagement and record it. */
        in events : EngagementEvents;
        in plan : EngagementPlan;
        out result : EngagementRecord = report.result;
        action judge : JudgeEngagement { in events = Assess::events; }
        action report : ReportOutcome { in assessment = judge.result; in plan = Assess::plan; }
    }
}
