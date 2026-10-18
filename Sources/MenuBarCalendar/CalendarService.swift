import Foundation

/// Fetches today's events from the Google Calendar API for the primary
/// calendar of the connected account. Multi-calendar support (step 4) will
/// loop this over each connected account's calendar list instead.
enum CalendarService {
    enum ServiceError: Error { case badResponse }

    static func fetchTodayEvents(accessToken: String, calendarName: String, completion: @escaping (Result<[Event], Error>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso8601(startOfDay)),
            URLQueryItem(name: "timeMax", value: iso8601(endOfDay)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[CalendarService] network error: \(error)")
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                print("[CalendarService] request failed, status \(http.statusCode): \(body)")
            }
            guard let data else {
                completion(.failure(ServiceError.badResponse))
                return
            }
            do {
                let list = try JSONDecoder().decode(EventListResponse.self, from: data)
                let events = list.items.compactMap { $0.toEvent(calendarName: calendarName) }
                for event in events {
                    print("[CalendarService] event: \(event.title) | \(event.start) - \(event.end)")
                }
                print("[CalendarService] fetched \(events.count) parsed of \(list.items.count) raw items, now=\(Date())")
                completion(.success(events))
            } catch {
                print("[CalendarService] decode error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private struct EventListResponse: Decodable {
        let items: [GoogleEvent]
    }

    private struct GoogleEvent: Decodable {
        struct EventDateTime: Decodable {
            let dateTime: String?
            let date: String?
        }
        struct ConferenceData: Decodable {
            struct EntryPoint: Decodable {
                let entryPointType: String?
                let uri: String?
            }
            let entryPoints: [EntryPoint]?
        }

        let summary: String?
        let start: EventDateTime
        let end: EventDateTime
        let hangoutLink: String?
        let conferenceData: ConferenceData?

        func toEvent(calendarName: String) -> Event? {
            guard let start = Self.parse(start), let end = Self.parse(end) else { return nil }
            return Event(
                title: summary ?? "(No title)",
                calendarName: calendarName,
                start: start,
                end: end,
                meetLink: resolvedMeetLink
            )
        }

        /// Google gives a direct `hangoutLink` for classic Meet events, but
        /// events with other conferencing (or added via "Add conferencing")
        /// only populate `conferenceData.entryPoints` — check both.
        private var resolvedMeetLink: URL? {
            if let hangoutLink, let url = URL(string: hangoutLink) {
                return url
            }
            let videoURI = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri
            return videoURI.flatMap(URL.init(string:))
        }

        private static func parse(_ dt: EventDateTime) -> Date? {
            if let dateTime = dt.dateTime {
                return ISO8601DateFormatter().date(from: dateTime)
            }
            if let date = dt.date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: date)
            }
            return nil
        }
    }
}
