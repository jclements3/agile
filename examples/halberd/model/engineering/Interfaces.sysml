// Segment E (Systems Engineering & Integration): ports and interface definitions between segments.
package InterfaceDefinitions {
    doc /* Every segment boundary is a port definition plus an interface definition that joins two ports. */
    private import KillChainItems::**;
    private import SecMeta::*;
    @Marking { level = Level::U; }

    port def SensorDataPort { doc /* Sensor reports out of a sensor. */ out item reports : DetectionSet; }
    port def UplinkPort { doc /* In-flight updates to an interceptor. */ out item updates : InflightUpdates; }
    port def LaunchCommandPort { doc /* Launch commands to a launcher. */ out item command : EngagementPlan; }
    port def TacticalLinkPort { doc /* Track and status exchange with external units. */ inout item picture : TrackSet; }
    port def MaintenanceDataPort { doc /* Health and fault data for maintainers. */ out item health : HealthReport; }

    interface def SensorReportInterface { end producer : SensorDataPort; end consumer : ~SensorDataPort; }
    interface def InflightUplinkInterface { end transmitter : UplinkPort; end receiver : ~UplinkPort; }
    interface def LaunchControlInterface { end commander : LaunchCommandPort; end launcher : ~LaunchCommandPort; }
    interface def MaintenanceDataInterface { end source : MaintenanceDataPort; end sink : ~MaintenanceDataPort; }
}
