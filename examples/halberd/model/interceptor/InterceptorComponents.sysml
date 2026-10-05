// Segment V (Interceptor Development): the round's assemblies.
package InterceptorComponents {
    doc /* Assemblies of the booster, the kill vehicle and the avionics section. */
    private import Conventions::*;
    private import SeekerComponents::*;

    part def RocketMotor { @L5Assembly; doc /* The booster motor. */ }
    part def ThrustVectorControl { @L5Assembly; doc /* Steers the booster. */ }
    part def Seeker {
        @L5Assembly;
        doc /* The kill vehicle's own sensor for terminal homing. */
        part optics : SeekerOptics;
        part focalPlane : FocalPlaneArray;
        part cooler : Cryocooler;
    }
    part def DivertSystem { @L5Assembly; doc /* Moves the kill vehicle sideways in the endgame. */ }
    part def GuidanceProcessor { @L5Assembly; doc /* Runs the kill vehicle's guidance. */ }
    part def FlightComputer { @L5Assembly; doc /* Runs the round's flight software. */ }
    part def DataLinkTransceiver { @L5Assembly; doc /* Receives in-flight updates. */ }
    part def ThermalBattery { @L5Assembly; doc /* Powers the round in flight. */ }
}
