import UIKit

enum HapticFeedback {
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let lightGenerator        = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator       = UIImpactFeedbackGenerator(style: .medium)
    private static let softGenerator         = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidGenerator        = UIImpactFeedbackGenerator(style: .rigid)

    static func success() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }
    static func error() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.error)
    }
    static func light() {
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }
    static func medium() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }
    static func soft() {
        softGenerator.prepare()
        softGenerator.impactOccurred()
    }
    static func rigid() {
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred()
    }
}
