// Segment V (Interceptor Development): the seeker's components, the deepest level of the part tree.
package SeekerComponents {
    doc /* Components of the seeker. */
    private import Conventions::*;

    part def SeekerOptics { @L6Component; doc /* Collects the scene. */ }
    part def FocalPlaneArray { @L6Component; doc /* Turns the scene into an image. */ }
    part def Cryocooler { @L6Component; doc /* Keeps the focal plane cold. */ }
}
