import AppKit
import SwiftUI

/// Shows a single one-time hint callout near the ghost text overlay.
/// The panel is non-activating, auto-dismisses after 4 seconds, and is never shown for the same
/// hint twice — tracked by `FeatureSpotlightStore`. All visibility logic lives here so callers
/// only need to call `showIfNeeded(_:near:)` at the relevant trigger point.
@MainActor
final class FeatureSpotlightController {
    private static let autoDismissDelay: TimeInterval = 4.5
    private static let verticalOffset: CGFloat = -36

    private lazy var panel: NSPanel = {
        let p = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.animationBehavior = .none
        return p
    }()

    private var dismissWorkItem: DispatchWorkItem?
    private let store: FeatureSpotlightStore

    init(store: FeatureSpotlightStore) {
        self.store = store
    }

    /// Shows the hint callout below `anchorRect` (screen coordinates) if this hint hasn't been
    /// shown before. Safe to call on every suggestion — returns immediately if already shown.
    func showIfNeeded(_ hint: FeatureSpotlightStore.Hint, near anchorRect: CGRect) {
        guard store.shouldShow(hint) else { return }

        let hostingView = NSHostingView(rootView: SpotlightCalloutView(message: hint.message))
        hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
        panel.contentView = hostingView

        let size = hostingView.fittingSize
        let originX = anchorRect.minX
        let originY = anchorRect.minY + Self.verticalOffset - size.height
        panel.setFrame(CGRect(x: originX, y: originY, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }

        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.dismissAnimated()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: item)
    }

    private func dismissAnimated() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}

// MARK: - Callout view

private struct SpotlightCalloutView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        )
    }
}
