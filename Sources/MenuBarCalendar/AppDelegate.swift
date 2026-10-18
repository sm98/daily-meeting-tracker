import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var hostingController: NSHostingController<ContentView>!
    private var countdownTimer: Timer?
    private var eventsRefreshTimer: Timer?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var eventsCancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    private let eventStore = EventStore()

    private let panelWidth: CGFloat = 280

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "Loading…"
            button.action = #selector(toggleClicked)
            button.target = self
        }

        hostingController = NSHostingController(
            rootView: ContentView(eventStore: eventStore, onSettingsTapped: { [weak self] in
                self?.showSettings()
            })
        )
        hostingController.sizingOptions = [.preferredContentSize]
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 1),
            contentViewController: hostingController
        )

        eventsCancellable = eventStore.$events.sink { [weak self] _ in
            self?.updateStatusTitle()
        }

        eventStore.refresh()
        updateStatusTitle()

        // Countdown labels tick every 30s; the actual event list is
        // refetched from Google less often to stay well under API quota.
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateStatusTitle()
        }
        eventsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.eventStore.refresh()
        }
    }

    @objc private func toggleClicked() {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let fitting = hostingController.view.fittingSize
        let panelHeight = max(fitting.height, 120)
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        let buttonFrame = buttonWindow.frame
        let x = buttonFrame.minX
        let y = buttonFrame.minY - panelHeight - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startOutsideClickMonitors()
    }

    private func closePanel() {
        panel.orderOut(nil)
        stopOutsideClickMonitors()
    }

    /// NSPopover auto-dismisses on outside clicks for free; a borderless
    /// NSPanel doesn't, so we watch for clicks outside it ourselves.
    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window == self.panel {
                return event
            }
            self.closePanel()
            return event
        }
    }

    private func stopOutsideClickMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    private func updateStatusTitle() {
        statusItem.button?.title = eventStore.statusBarTitle()
    }

    private func showSettings() {
        closePanel()

        if settingsWindow == nil {
            let settingsView = SettingsView(onAccountsChanged: { [weak self] in
                self?.eventStore.refresh()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: settingsView)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
