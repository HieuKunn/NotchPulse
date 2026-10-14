import SwiftUI

enum FaceIDOverlayPanelStyle {
    /// Inverted top corners, flush with the screen's top edge.
    case notch
    /// Fully-rounded pill / floating rounded rectangle, detached from the edge.
    case pill
}

extension EnvironmentValues {
    @Entry var notchPanelStyle: FaceIDOverlayPanelStyle = .notch
}

typealias NotchPanelStyle = FaceIDOverlayPanelStyle
