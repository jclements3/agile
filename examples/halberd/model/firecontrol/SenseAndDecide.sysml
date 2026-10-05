// Segment B (Battle Management & Fire Control): the leaf functions of detect, track, identify and decide.
package SenseAndDecide {
    doc /* Leaf functions from sensor returns to the engagement plan. */
    private import KillChainItems::**;

    action def ConditionSignals { doc /* Filter and calibrate raw returns. */ in returns : SensorReturns; out result : ConditionedSignals; }
    action def DeclareDetections { doc /* Declare detections where the sensors are tasked. */ in signals : ConditionedSignals; in tasking : SensorTasking; out result : DetectionSet; }
    action def AssociateDetections { doc /* Pair each detection with a track, or start a new one. */ in detections : DetectionSet; out result : Associations; }
    action def MaintainTracks { doc /* Update, start and drop tracks. */ in associations : Associations; out result : TrackSet; }
    action def CharacterizeTracks { doc /* Collect what is observed about each track. */ in tracks : TrackSet; out result : TrackFeatures; }
    action def ClassifyThreats { doc /* Match track features against the threat library. */ in features : TrackFeatures; in catalog : ThreatLibrary; out result : ClassifiedTrackSet; }
    action def EvaluateThreats { doc /* Order the threats under the doctrine. */ in threats : ClassifiedTrackSet; in doctrine : EngagementDoctrine; out result : ThreatPriorities; }
    action def PairWeapons { doc /* Assign available interceptors to the ranked threats. */ in priorities : ThreatPriorities; out result : WeaponPairings; }
    action def ScheduleEngagements { doc /* Schedule launches, only once fire is authorized. */ in pairings : WeaponPairings; in authority : FireAuthorization; out result : EngagementPlan; }
}
