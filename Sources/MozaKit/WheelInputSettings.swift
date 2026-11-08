import Foundation

/// User input shaping and button-to-axis/keyboard routing; never emits HID output.
public struct WheelInputSettings: Codable, Equatable {
    public var steeringGamma = 1.0
    public var steeringDeadzone = 0.0
    public var steeringSaturation = 1.0
    public var steeringScale = 1.0
    public var steeringFilter = 0.0
    public var speedSensitivity = 0.0
    public var brakeGamma = 1.0
    public var throttleGamma = 1.0
    public var clutchReleaseMilliseconds = 0.0
    public init() {}
    public func steering(_ position: Double) -> Double {
        let deadzone = max(0, min(0.2, steeringDeadzone))
        let saturation = max(deadzone + 0.05, min(1, steeringSaturation))
        let value = max(0, min(1, (abs(position) - deadzone) / (saturation - deadzone)))
        return (position < 0 ? -1 : 1) * pow(value, max(0.25, min(4, steeringGamma)))
    }
    public static let fileName = "bridge-controls.json"
}

public struct BridgeControlConfiguration: Codable {
    public var tuning = WheelInputSettings()
    public var bindings: [String: Int] = [:]
    public init(tuning: WheelInputSettings = .init(), bindings: [String: Int] = [:]) {
        self.tuning = tuning; self.bindings = bindings
    }
    public static func load(url: URL) -> Self {
        (try? JSONDecoder().decode(Self.self, from: Data(contentsOf: url))) ?? .init()
    }
    public func actions(pressed: Set<Int>) -> UInt32 {
        let names = ["BRIDGE_ESCAPE", "BRIDGE_ENTER", "BRIDGE_LEFT", "BRIDGE_RIGHT", "BRIDGE_UP", "BRIDGE_DOWN"]
        var result: UInt32 = 0
        for (i, name) in names.enumerated() {
            if let button = bindings[name], pressed.contains(button) { result |= 1 << UInt32(i) }
        }
        return result
    }
}
