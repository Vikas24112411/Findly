import SwiftUI

// MARK: - Design tokens for the Findly design system.
// Use these throughout the app instead of hard-coded values.

enum AppTheme {

    // MARK: - Colors

    enum Colors {
        static let accent         = Color(hex: "#1F90E4")
        static let background     = Color(UIColor.systemBackground)
        static let secondaryBG    = Color(UIColor.secondarySystemBackground)
        static let tertiaryBG     = Color(UIColor.tertiarySystemBackground)
        static let groupedBG      = Color(UIColor.systemGroupedBackground)
        static let label          = Color(UIColor.label)
        static let secondaryLabel = Color(UIColor.secondaryLabel)
        static let tertiaryLabel  = Color(UIColor.tertiaryLabel)
        static let separator      = Color(UIColor.separator)
        static let fill           = Color(UIColor.systemFill)
        static let secondaryFill  = Color(UIColor.secondarySystemFill)

        // File type tints
        static let imageTint    = Color(hex: "#FF6B6B")
        static let videoTint    = Color(hex: "#4ECDC4")
        static let audioTint    = Color(hex: "#45B7D1")
        static let pdfTint      = Color(hex: "#E74C3C")
        static let documentTint = Color(hex: "#3498DB")
        static let noteTint     = Color(hex: "#F39C12")
        static let linkTint     = Color(hex: "#9B59B6")
        static let archiveTint  = Color(hex: "#1ABC9C")
        static let otherTint    = Color(hex: "#95A5A6")

        // Sync status tints
        static let syncLocalOnly = Color(UIColor.systemGray)
        static let syncPending   = Color(hex: "#F39C12")
        static let syncSyncing   = Color(hex: "#3498DB")
        static let syncSynced    = Color(hex: "#2ECC71")
        static let syncFailed    = Color(hex: "#E74C3C")
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle   = Font.largeTitle.weight(.bold)
        static let title1       = Font.title.weight(.semibold)
        static let title2       = Font.title2.weight(.semibold)
        static let title3       = Font.title3.weight(.medium)
        static let headline     = Font.headline
        static let body         = Font.body
        static let callout      = Font.callout
        static let subheadline  = Font.subheadline
        static let footnote     = Font.footnote
        static let caption1     = Font.caption
        static let caption2     = Font.caption2
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxSmall: CGFloat =  2
        static let xSmall:  CGFloat =  4
        static let small:   CGFloat =  8
        static let medium:  CGFloat = 12
        static let base:    CGFloat = 16
        static let large:   CGFloat = 20
        static let xLarge:  CGFloat = 24
        static let xxLarge: CGFloat = 32
        static let xxxLarge: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let small:  CGFloat =  8
        static let medium: CGFloat = 12
        static let large:  CGFloat = 16
        static let xLarge: CGFloat = 20
        static let full:   CGFloat = 999
    }

    // MARK: - Shadow

    enum Shadow {
        static let card   = (color: Color.black.opacity(0.08), radius: CGFloat(8),  x: CGFloat(0), y: CGFloat(2))
        static let raised = (color: Color.black.opacity(0.12), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(4))
        static let fab    = (color: Color.black.opacity(0.20), radius: CGFloat(12), x: CGFloat(0), y: CGFloat(6))
    }

    // MARK: - Animation

    enum Animation {
        static let fast:     SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.7)
        static let standard: SwiftUI.Animation = .spring(response: 0.45, dampingFraction: 0.8)
        static let slow:     SwiftUI.Animation = .spring(response: 0.6,  dampingFraction: 0.85)
        static let snappy:   SwiftUI.Animation = .spring(response: 0.25, dampingFraction: 0.9)
    }

    // MARK: - Icon sizes

    enum IconSize {
        static let small:  CGFloat = 16
        static let medium: CGFloat = 20
        static let large:  CGFloat = 24
        static let xLarge: CGFloat = 32
        static let fab:    CGFloat = 24
    }
}

// MARK: - File type color helper

extension FileType {
    var tintColor: Color {
        switch self {
        case .image:    return AppTheme.Colors.imageTint
        case .video:    return AppTheme.Colors.videoTint
        case .audio:    return AppTheme.Colors.audioTint
        case .pdf:      return AppTheme.Colors.pdfTint
        case .document: return AppTheme.Colors.documentTint
        case .note:     return AppTheme.Colors.noteTint
        case .link:     return AppTheme.Colors.linkTint
        case .archive:  return AppTheme.Colors.archiveTint
        case .other:    return AppTheme.Colors.otherTint
        }
    }
}

// MARK: - Sync status color helper

extension SyncStatus {
    var tintColor: Color {
        switch self {
        case .localOnly: return AppTheme.Colors.syncLocalOnly
        case .pending:   return AppTheme.Colors.syncPending
        case .syncing:   return AppTheme.Colors.syncSyncing
        case .synced:    return AppTheme.Colors.syncSynced
        case .failed:    return AppTheme.Colors.syncFailed
        }
    }
}
