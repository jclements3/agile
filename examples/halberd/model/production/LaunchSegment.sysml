// Segment M (Manufacturing & Production): the launch segment -- launchers and canisters -- which
// Manufacturing builds alongside the rounds. Structure only.
package Launch {
    doc /* Launchers and the canisters rounds are stored and launched from. */
    private import Conventions::*;
    private import InterfaceDefinitions::*;
    private import ProductionRequirements::*;

    part def LaunchSegment {
        @L2Segment;
        doc /* Every launcher and canister the program delivers. */
        part launcher : Launcher;
        part canisters : LaunchCanister;

        satisfy prdR01 by canisters;
        satisfy prdR02 by canisters;
        satisfy prdR03 by canisters;
        satisfy prdR04 by launcher;
    }
    part def Launcher {
        @L3System;
        doc /* Holds canisters, raises them and fires them on command. */
        part electronics : LauncherElectronics;
        part erector : ErectorAssembly;
        part power : PowerUnit;
        port launchIn : ~LaunchCommandPort;
        port maintenance : MaintenanceDataPort;
    }
    part def LaunchCanister {
        @L3System;
        doc /* A sealed canister: storage, shipping and launch tube for one round. */
        part shell : CanisterShell;
        part umbilical : CanisterUmbilical;
    }
    part def LauncherElectronics { @L4Subsystem; doc /* Checks launch commands and sequences the launch. */ }
    part def ErectorAssembly { @L4Subsystem; doc /* Raises the canisters to launch position. */ }
    part def PowerUnit { @L4Subsystem; doc /* Powers the launcher. */ }
    part def CanisterShell { @L4Subsystem; doc /* The canister's structure and seals. */ }
    part def CanisterUmbilical { @L4Subsystem; doc /* Power and data between launcher and round. */ }
}
