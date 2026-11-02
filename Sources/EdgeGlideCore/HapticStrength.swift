/// User-facing haptic strength. The app maps each level to a private
/// MTActuator actuation, or to an NSHapticFeedbackManager pattern.
public enum HapticStrength: String, CaseIterable, Sendable, Identifiable {
    case off
    case weak
    case medium
    case strong

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .weak: "Weak"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }
}
