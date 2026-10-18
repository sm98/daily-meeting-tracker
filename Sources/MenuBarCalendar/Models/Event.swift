import Foundation

struct Event: Identifiable {
    let id = UUID()
    let title: String
    let calendarName: String
    let start: Date
    let end: Date
    let meetLink: URL?
}

final class EventStore: ObservableObject {
    @Published var events: [Event] = []
    @Published var isLoading = false

    private let auth = GoogleAuthManager.shared

    init() {
        events = auth.accounts.isEmpty ? EventStore.sampleEvents() : []
    }

    /// Pulls fresh events from every connected account and merges them into
    /// one sorted list; falls back to sample data if nothing's connected
    /// yet so the UI still has something to show pre-OAuth setup.
    func refresh() {
        let accounts = auth.accounts
        print("[EventStore] refresh() called, accounts=\(accounts.map(\.email))")
        guard !accounts.isEmpty else {
            events = EventStore.sampleEvents()
            return
        }

        isLoading = true
        var collected: [Event] = []
        let group = DispatchGroup()

        for account in accounts {
            group.enter()
            auth.fetchAccessToken(for: account) { result in
                switch result {
                case .success(let token):
                    CalendarService.fetchTodayEvents(accessToken: token, calendarName: account.label) { result in
                        if case .success(let events) = result {
                            collected.append(contentsOf: events)
                        } else if case .failure(let error) = result {
                            print("[EventStore] fetch failed for \(account.email): \(error)")
                        }
                        group.leave()
                    }
                case .failure(let error):
                    print("[EventStore] fetchAccessToken failed for \(account.email): \(error)")
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isLoading = false
            self.events = collected.sorted { $0.start < $1.start }
            print("[EventStore] merged \(self.events.count) events from \(accounts.count) account(s)")
        }
    }

    static func sampleEvents() -> [Event] {
        let cal = Calendar.current
        let now = Date()

        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = minute
            return cal.date(from: comps) ?? now
        }

        return [
            Event(title: "Design sync", calendarName: "Work", start: at(19, 30), end: at(19, 45), meetLink: nil),
            Event(title: "1:1 with Sam", calendarName: "Work", start: at(20, 0), end: at(21, 0), meetLink: URL(string: "https://meet.google.com/abc-defg-hij")),
            Event(title: "Team standup", calendarName: "Work", start: at(21, 30), end: at(22, 30), meetLink: nil),
            Event(title: "Dinner", calendarName: "Personal", start: at(23, 0), end: at(23, 59), meetLink: nil)
        ].sorted { $0.start < $1.start }
    }

    func nextOrCurrentEvent() -> Event? {
        let now = Date()
        return events.first { $0.end > now }
    }

    /// Today's events excluding whichever one is shown in the "next meeting"
    /// section up top.
    func remainingTodayEvents() -> [Event] {
        let now = Date()
        guard let next = nextOrCurrentEvent() else { return [] }
        return events.filter { $0.id != next.id && $0.end > now }
    }

    func countdownLabel(for event: Event) -> String {
        let now = Date()
        if event.start <= now {
            let mins = max(0, Int(event.end.timeIntervalSince(now) / 60))
            return "Ends in \(Self.formatMinutes(mins))"
        } else {
            let mins = max(0, Int(event.start.timeIntervalSince(now) / 60))
            return "Starts in \(Self.formatMinutes(mins))"
        }
    }

    func statusBarTitle() -> String {
        guard let event = nextOrCurrentEvent() else { return "No events" }
        let now = Date()
        if event.start <= now {
            let mins = max(0, Int(event.end.timeIntervalSince(now) / 60))
            return "\(event.title) · \(Self.formatMinutes(mins)) left"
        } else {
            let mins = max(0, Int(event.start.timeIntervalSince(now) / 60))
            return "\(event.title) · in \(Self.formatMinutes(mins))"
        }
    }

    private static func formatMinutes(_ totalMinutes: Int) -> String {
        guard totalMinutes >= 60 else { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }
}
