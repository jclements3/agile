// Segment B (Battle Management & Fire Control): the information that flows along the kill chain.
// Notional: each item is a named flow, with no content modeled.
package KillChainItems {
    doc /* The flows between kill-chain functions -- what each step takes in and hands on -- and the health data equipment reports. */
    private import SecMeta::*;
    @Marking { level = Level::U; }

    package Inputs {
        doc /* What the kill chain receives from outside: the mission inputs record and its fields. */
        item def MissionInputs {
            doc /* Everything the kill chain is given: returns to process and the rules to apply. */
            item sensorReturns : SensorReturns;
            item tasking : SensorTasking;
            item threatLibrary : ThreatLibrary;
            item doctrine : EngagementDoctrine;
            item authority : FireAuthorization;
        }
        item def SensorReturns { doc /* Raw returns from the sensors. */ }
        item def SensorTasking { doc /* Where the sensors are told to look. */ }
        item def ThreatLibrary { doc /* The reference descriptions threats are classified against. */ }
        item def EngagementDoctrine { doc /* The rules that order threats and choose responses. */ }
        item def FireAuthorization { doc /* The operator's permission to launch. */ }
    }

    package Products {
        doc /* What sensing and tracking produce. */
        item def ConditionedSignals { doc /* Returns filtered and calibrated. */ }
        item def DetectionSet { doc /* Declared detections. */ }
        item def Associations { doc /* Detections paired with existing tracks. */ }
        item def TrackSet { doc /* The maintained tracks. */ }
        item def TrackFeatures { doc /* What has been observed about each track. */ }
        item def ClassifiedTrackSet { doc /* Tracks with a threat classification. */ }
    }

    package EngagementData {
        doc /* What deciding, engaging and assessing produce. */
        item def ThreatPriorities { doc /* Threats in the order they should be engaged. */ }
        item def WeaponPairings { doc /* Which interceptor is assigned to which threat. */ }
        item def EngagementPlan { doc /* The authorized launch schedule. */ }
        item def LaunchEvent { doc /* A launch that has happened. */ }
        item def InflightUpdates { doc /* Track updates sent to an interceptor in flight. */ }
        item def EngagementEvents { doc /* What happened during the engagement. */ }
        item def KillAssessment { doc /* The judgement of whether the threat was defeated. */ }
        item def EngagementRecord { doc /* The complete record of one engagement. */ }
    }

    item def HealthReport { doc /* Health and fault data from a launcher or a round, for maintainers (not a kill-chain flow). */ }
}
