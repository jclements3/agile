package HalberdViews {
    doc /* Views published as drawing plates. Notional. */
    private import SecMeta::*;
    private import DrawingMeta::*;
    @Marking { level = Level::U; }

    view def DecompositionView { filter @SysML::PartUsage; }
    view def ConnectionView;
    view def SecurityTable { filter @SecurityRequirement; }
    view def PackageView;

    view <'HAL-DWG-001'> enterpriseDecomposition : DecompositionView {
        doc /* IAMD enterprise decomposition. Shapes only. */
        @Drawing { revision = "A"; drawnBy = "J. Clements"; }
        expose IAMDSketch::IAMDEnterpriseDef;
        render asTreeDiagram;
    }
    view <'HAL-DWG-002'> flightTestWiring : ConnectionView {
        doc /* Flight-test telemetry path with trust zones. */
        expose HalberdFlightTest::**;
        render asInterconnectionDiagram;
    }
    view <'HAL-DWG-003'> securityTrace {
        doc /* Security requirements and their verification. */
        expose HalberdSecurityRequirements::**;
        filter @SysML::RequirementUsage;
        render asTreeDiagram;
    }
    view <'HAL-DWG-004'> securityTable : SecurityTable {
        expose HalberdSecurityRequirements::**;
        render asElementTable;
    }
    view <'HAL-DWG-005'> packageMap : PackageView;
    view <'HAL-DWG-006'> gatewaySource {
        doc /* Range gateway definition as text. */
        expose HalberdFlightTest::RangeGateway;
        render asTextualNotation;
    }
    view <'HAL-DWG-007'> stateMachines {
        expose HalberdFlightTest::**;
        render asStateTransitionDiagram;
    }
}
