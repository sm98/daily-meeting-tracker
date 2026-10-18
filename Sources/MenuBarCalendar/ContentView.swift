import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var eventStore: EventStore
    var onSettingsTapped: () -> Void = {}

    private let cornerRadius: CGFloat = 18
    private let panelWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = eventStore.nextOrCurrentEvent() {
                nextMeetingSection(next)
                InsetDivider()
            }

            todaySection

            InsetDivider()

            VStack(alignment: .leading, spacing: 2) {
                MenuButton(title: "Open Granola") {
                    openGranola()
                }
                MenuButton(title: "Settings") {
                    onSettingsTapped()
                }
                MenuButton(title: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: panelWidth)
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                Color.black.opacity(0.05)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func nextMeetingSection(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eventStore.countdownLabel(for: event))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            EventRow(event: event)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))

            let remaining = eventStore.remainingTodayEvents()
            if remaining.isEmpty {
                Text("No more meetings today")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(remaining) { event in
                    EventRow(event: event)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Granola has no documented URL param for pre-filling a note title, so
    /// the practical bridge is copying the meeting title to the clipboard
    /// right before switching to the app, ready to paste into the note.
    private func openGranola() {
        if let event = eventStore.nextOrCurrentEvent() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(event.title, forType: .string)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.granola.app") {
            NSWorkspace.shared.open(url)
        } else if let scheme = URL(string: "granola://") {
            NSWorkspace.shared.open(scheme)
        }
    }
}

private struct InsetDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.15))
            .padding(.horizontal, 14)
    }
}

private struct EventRow: View {
    let event: Event

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: event.start)) - \(formatter.string(from: event.end))"
    }

    var body: some View {
        Button {
            if let meetLink = event.meetLink {
                NSWorkspace.shared.open(meetLink)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    if event.meetLink != nil {
                        Image(systemName: "video.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Text("\(timeRange) · \(event.calendarName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .disabled(event.meetLink == nil)
    }
}

private struct MenuButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }
}
