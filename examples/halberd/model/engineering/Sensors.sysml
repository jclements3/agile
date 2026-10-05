// Segment E (Systems Engineering & Integration): the sensor segment, integrated by SE&I from
// government-furnished sensors. Structure only.
package Sensors {
    doc /* The sensors that find and report objects in the surveillance volume. */
    private import Conventions::*;
    private import InterfaceDefinitions::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    part def SensorSegment {
        @L2Segment;
        doc /* Every sensor that feeds fire control. */
        part surveillanceRadar : SurveillanceRadar;
        part passiveSensor : PassiveSensor;
    }
    part def SurveillanceRadar {
        @L3System;
        doc /* The primary search and track sensor. */
        part antenna : AntennaArray;
        part receiverExciter : ReceiverExciter;
        part signalProcessor : SignalProcessor;
        port reports : SensorDataPort;
    }
    part def PassiveSensor {
        @L3System;
        doc /* A passive sensor that cues and confirms. */
        part sensorHead : SensorHead;
        part gimbal : Gimbal;
        port reports : SensorDataPort;
    }
    part def AntennaArray { @L4Subsystem; doc /* The radar's antenna. */ }
    part def ReceiverExciter { @L4Subsystem; doc /* Generates the transmitted signal and receives the returns. */ }
    part def SignalProcessor { @L4Subsystem; doc /* Turns returns into detections. */ }
    part def SensorHead { @L4Subsystem; doc /* The passive sensor's detector and optics. */ }
    part def Gimbal { @L4Subsystem; doc /* Points the sensor head. */ }
}
