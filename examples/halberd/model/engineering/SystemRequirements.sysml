// Segment E (Systems Engineering & Integration): the system requirements, derived from the
// stakeholder needs. Each carries its DOORS id; satisfy and verify relationships live with the
// parts that satisfy them and with the verification cases (segment T).
package SystemRequirements {
    doc /* The Halberd system specification. */

    package Functions {
        doc /* What the system shall do, one kill-chain step at a time. */
        requirement sysF01 { attribute doorsId = "HAL-SYS-001"; doc /* The system shall detect objects in its assigned surveillance volume. */ }
        requirement sysF02 { attribute doorsId = "HAL-SYS-002"; doc /* The system shall form and maintain a track on every detected object. */ }
        requirement sysF03 { attribute doorsId = "HAL-SYS-003"; doc /* The system shall classify each track against the threat library. */ }
        requirement sysF04 { attribute doorsId = "HAL-SYS-004"; doc /* The system shall evaluate and prioritize threats under the engagement doctrine. */ }
        requirement sysF05 { attribute doorsId = "HAL-SYS-005"; doc /* The system shall pair available interceptors with prioritized threats. */ }
        requirement sysF06 { attribute doorsId = "HAL-SYS-006"; doc /* The system shall not launch without an operator fire authorization. */ }
        requirement sysF07 { attribute doorsId = "HAL-SYS-007"; doc /* The system shall launch an interceptor and guide it to the threat. */ }
        requirement sysF08 { attribute doorsId = "HAL-SYS-008"; doc /* The system shall assess the outcome of every engagement. */ }
        requirement sysF09 { attribute doorsId = "HAL-SYS-009"; doc /* The system shall record every engagement for after-action review. */ }
    }

    package Exchanges {
        doc /* What the system shall exchange across its segment and external boundaries. */
        requirement sysX01 { attribute doorsId = "HAL-SYS-010"; doc /* Sensors shall report detections to fire control over the sensor report interface. */ }
        requirement sysX02 { attribute doorsId = "HAL-SYS-011"; doc /* Fire control shall send in-flight updates to interceptors over the uplink. */ }
        requirement sysX03 { attribute doorsId = "HAL-SYS-012"; doc /* Fire control shall command launchers over the launch control interface. */ }
        requirement sysX04 { attribute doorsId = "HAL-SYS-013"; doc /* The system shall exchange tactical data with higher echelon command. */ }
        requirement sysX05 { attribute doorsId = "HAL-SYS-014"; doc /* The system shall share tracks with adjacent defense units. */ }
        requirement sysX06 { attribute doorsId = "HAL-SYS-015"; doc /* Launchers and rounds shall report health data to the support segment. */ }
        requirement sysX07 { attribute doorsId = "HAL-SYS-016"; doc /* All segments shall use a common time reference. */ }
    }

    package Security {
        doc /* How the system shall protect its data and control paths. */
        requirement secR01 { attribute doorsId = "HAL-SYS-020"; doc /* The system shall authenticate every message on external tactical links. */ }
        requirement secR02 { attribute doorsId = "HAL-SYS-021"; doc /* The system shall encrypt the in-flight uplink. */ }
        requirement secR03 { attribute doorsId = "HAL-SYS-022"; doc /* Launchers shall execute only authenticated launch commands. */ }
        requirement secR04 { attribute doorsId = "HAL-SYS-023"; doc /* Every software build shall be signed, and the signature checked before loading. */ }
        requirement secR05 { attribute doorsId = "HAL-SYS-024"; doc /* The maintenance network shall be isolated from the tactical network. */ }
        requirement secR06 { attribute doorsId = "HAL-SYS-025"; doc /* The system shall log security-relevant events for audit. */ }
        requirement secR07 { attribute doorsId = "HAL-SYS-026"; doc /* Operator functions shall be limited by role. */ }
    }

    package Lifecycle {
        doc /* How the system shall be maintained, moved, trained on and documented. */
        requirement sysL01 { attribute doorsId = "HAL-SYS-030"; doc /* Each line-replaceable unit shall report its own faults through built-in test. */ }
        requirement sysL02 { attribute doorsId = "HAL-SYS-031"; doc /* Rounds in storage shall be monitored for health without being unpacked. */ }
        requirement sysL03 { attribute doorsId = "HAL-SYS-032"; doc /* Every segment shall be transportable by the fielding unit's standard vehicles. */ }
        requirement sysL04 { attribute doorsId = "HAL-SYS-033"; doc /* Every line-replaceable unit shall carry its configuration identification. */ }
        requirement sysL05 { attribute doorsId = "HAL-SYS-034"; doc /* The system shall provide a training mode with simulated threats. */ }
        requirement sysL06 { attribute doorsId = "HAL-SYS-035"; doc /* Technical data shall be delivered in digital form. */ }
    }
}
