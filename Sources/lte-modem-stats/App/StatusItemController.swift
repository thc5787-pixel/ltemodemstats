import AppKit
import ModemCore
import SwiftUI

/// Owns the menu bar item and its popover, and redraws the item when the service changes.
@MainActor
final class StatusItemController: NSObject {
    private let service: ModemService
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var lastPresentation: MenuBarPresentation?

    init(service: ModemService) {
        self.service = service
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PanelView(service: service, ui: PanelState()))

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }
        observe()
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            service.settings.refreshLaunchAtLogin()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Re-renders whenever any observed property changes.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render() {
        // Labels come from L10n; reading the setting makes a language change re-render.
        _ = service.settings.language
        let presentation = MenuBarPresentation(
            connection: service.connection,
            status: service.status,
            rates: service.meter.session == nil ? nil : (service.meter.rxRate, service.meter.txRate),
            showRates: service.settings.showRateInMenuBar,
            quotaFraction: service.quotaFraction
        )
        guard presentation != lastPresentation, let button = item.button else { return }
        lastPresentation = presentation

        button.image = StatusIcon.image(bars: presentation.bars, active: presentation.active, tint: presentation.tint)
        button.attributedTitle = Self.title(presentation)
        button.toolTip = presentation.tooltip
    }

    private static func title(_ presentation: MenuBarPresentation) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString(string: " " + presentation.label, attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize - 1, weight: .medium),
            .baselineOffset: 0.5,
        ])
        if let rates = presentation.rates {
            title.append(NSAttributedString(string: " " + rates, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize - 3, weight: .regular),
                .baselineOffset: 1,
            ]))
        }
        return title
    }
}
