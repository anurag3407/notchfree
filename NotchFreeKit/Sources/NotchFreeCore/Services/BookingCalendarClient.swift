import Foundation
import Security

public enum KeychainSecretStore {
    private static let service = "com.notchfree.app.secrets"

    @discardableResult
    public static func save(key: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    public static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum BookingCalendarClient {
    public static let calendlyKeyName = "calendly_api_key"
    public static let calComKeyName = "calcom_api_key"

    public static func fetchCalendlyEvents(apiKey: String, now: Date = Date()) async throws -> [CalendarTimeBlock] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var userReq = URLRequest(url: URL(string: "https://api.calendly.com/users/me")!)
        userReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (userData, _) = try await URLSession.shared.data(for: userReq)
        let userObj = try JSONSerialization.jsonObject(with: userData) as? [String: Any]
        guard let resource = userObj?["resource"] as? [String: Any],
              let userURI = resource["uri"] as? String else {
            return []
        }

        let iso = ISO8601DateFormatter()
        let minStart = iso.string(from: now)
        let maxStart = iso.string(from: Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now)
        var comps = URLComponents(string: "https://api.calendly.com/scheduled_events")!
        comps.queryItems = [
            URLQueryItem(name: "user", value: userURI),
            URLQueryItem(name: "status", value: "active"),
            URLQueryItem(name: "min_start_time", value: minStart),
            URLQueryItem(name: "max_start_time", value: maxStart)
        ]

        var eventsReq = URLRequest(url: comps.url!)
        eventsReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (eventsData, _) = try await URLSession.shared.data(for: eventsReq)
        return parseCalendlyPayload(eventsData)
    }

    public static func parseCalendlyPayload(_ data: Data) -> [CalendarTimeBlock] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let collection = json["collection"] as? [[String: Any]] else {
            return []
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackISO = ISO8601DateFormatter()

        return collection.compactMap { item in
            guard let name = item["name"] as? String,
                  let startStr = item["start_time"] as? String,
                  let endStr = item["end_time"] as? String,
                  let start = iso.date(from: startStr) ?? fallbackISO.date(from: startStr),
                  let end = iso.date(from: endStr) ?? fallbackISO.date(from: endStr) else {
                return nil
            }
            let locationDict = item["location"] as? [String: Any]
            let joinURL = (locationDict?["join_url"] as? String).flatMap(URL.init(string:))
            let locationText = locationDict?["location"] as? String
            return CalendarTimeBlock(
                id: (item["uri"] as? String) ?? UUID().uuidString,
                title: name,
                start: start,
                end: end,
                location: locationText,
                conferenceURL: joinURL,
                source: "Calendly"
            )
        }
    }

    public static func fetchCalComBookings(apiKey: String) async throws -> [CalendarTimeBlock] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var comps = URLComponents(string: "https://api.cal.com/v1/bookings")!
        comps.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return parseCalComPayload(data)
    }

    public static func parseCalComPayload(_ data: Data) -> [CalendarTimeBlock] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bookings = json["bookings"] as? [[String: Any]] else {
            return []
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackISO = ISO8601DateFormatter()

        return bookings.compactMap { item in
            let status = (item["status"] as? String)?.lowercased() ?? "accepted"
            guard status != "cancelled" else { return nil }
            guard let title = item["title"] as? String,
                  let startStr = item["startTime"] as? String,
                  let endStr = item["endTime"] as? String,
                  let start = iso.date(from: startStr) ?? fallbackISO.date(from: startStr),
                  let end = iso.date(from: endStr) ?? fallbackISO.date(from: endStr) else {
                return nil
            }
            let location = item["location"] as? String
            let joinURL = location.flatMap { str -> URL? in
                guard str.hasPrefix("http") else { return nil }
                return URL(string: str)
            }
            let idVal = (item["id"] as? Int).map(String.init) ?? UUID().uuidString
            return CalendarTimeBlock(
                id: "calcom-\(idVal)",
                title: title,
                start: start,
                end: end,
                location: location,
                conferenceURL: joinURL,
                source: "Cal.com"
            )
        }
    }
}
