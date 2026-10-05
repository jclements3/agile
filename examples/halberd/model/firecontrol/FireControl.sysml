// Segment B (Battle Management & Fire Control): the fire control segment's hardware.
package FireControl {
    doc /* The engagement control station and the communications node. */
    private import Conventions::*;
    private import InterfaceDefinitions::*;
    private import FireControlSoftwareDefs::*;
    private import FireControlRequirements::*;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    part def FireControlSegment {
        @L2Segment;
        doc /* Everything that turns sensor reports into engagements. */
        part engagementControlStation : EngagementControlStation;
        part communications : CommunicationsNode;
        part fireControlSoftware : FireControlSoftware;

        satisfy fcR04 by engagementControlStation;
        satisfy fcR06 by engagementControlStation;
        satisfy fcR08 by communications;
    }
    part def EngagementControlStation {
        @L3System;
        doc /* Where the crew supervises the kill chain and authorizes fire. */
        part console : OperatorConsole;
        part missionProcessor : MissionProcessor;
        port sensorIn : ~SensorDataPort;
        port launchOut : LaunchCommandPort;
    }
    part def CommunicationsNode {
        @L3System;
        doc /* The data links: in-flight uplink and external tactical links. */
        part dataLink : DataLinkTerminal;
        part crypto : CryptoUnit;
        port uplink : UplinkPort;
        port tacticalLink : TacticalLinkPort;
    }
    part def OperatorConsole { @L4Subsystem; doc /* The crew's displays and controls. */ }
    part def MissionProcessor { @L4Subsystem; doc /* Hosts the fire control software. */ }
    part def DataLinkTerminal { @L4Subsystem; doc /* Radio terminal for the uplink and the tactical links. */ }
    part def CryptoUnit { @L4Subsystem; doc /* Encrypts and authenticates link traffic. */ }
}
