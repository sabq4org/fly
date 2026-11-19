import SwiftUI

struct Trip: Identifiable, Codable {
    var id = UUID()
    var flight: FlightData
    var booking: String
    var seat: String
    var lookupNumber: String?
    var departureDay: String

    var scheduled: Date { flight.scheduledDepartureUTC ?? .distantFuture }
    var expected: Date { flight.revisedDepartureUTC ?? scheduled }
    var zone: TimeZone { TimeZone(identifier: flight.originTimeZone ?? "") ?? TimeZone(secondsFromGMT: 0)! }
    var completed: Bool {
        ["departed","airborne","enroute","approaching","arrived","landed","diverted"].contains(flight.status.lowercased())
    }
    var cancelled: Bool { ["canceled","cancelled"].contains(flight.status.lowercased()) }
    var delayMinutes: Int { max(0, Int((expected.timeIntervalSince(scheduled) / 60).rounded())) }
    func visible(at date: Date) -> Bool {
        let grace: TimeInterval = flight.status.lowercased() == "delayed" && flight.revisedDepartureUTC == nil ? 24 * 3600 : 90 * 60
        return !completed && date < max(expected, scheduled).addingTimeInterval(grace)
    }
    func ticketDue(at date: Date) -> Bool { date >= scheduled.addingTimeInterval(-5 * 3600) }
}

enum ClockText {
    static func string(_ date: Date, _ format: String, zone: TimeZone, arabic: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: arabic ? "ar_SA@numbers=latn" : "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = format
        return f.string(from: date)
    }

    static let cities = ["RUH":"الرياض","JED":"جدة","DMM":"الدمام","AHB":"أبها","MED":"المدينة المنورة",
                         "DXB":"دبي","AUH":"أبوظبي","DOH":"الدوحة","LHR":"لندن","CDG":"باريس","CAI":"القاهرة"]
    static func place(_ code: String?, _ name: String?) -> String {
        cities[code ?? ""] ?? name ?? code ?? "—"
    }
    static func countdown(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "حان موعد الإقلاع" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "باقي \(rest) د" }
        return rest == 0 ? "باقي \(hours) س" : "باقي \(hours) س و\(rest) د"
    }
}

@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published var notice: String?
    @Published private var failedRefreshTrip: UUID?
    func refreshMessage(for id: UUID) -> String? {
        failedRefreshTrip == id ? "تعذّر التحديث. معروضة آخر بيانات محفوظة." : nil
    }

    private var file: URL
    private var fetching = false
    private var attempted: [UUID: Date] = [:]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = dir.appendingPathComponent("flights.json")
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let fixture = args.first(where: { ["-test-empty","-test-active","-test-upcoming","-test-delayed","-test-resume"].contains($0) }) {
            file = dir.appendingPathComponent("qa-flights.json")
            if fixture != "-test-resume" {
                if fixture != "-test-empty" { trips = [Self.sample(fixture)] }
                try? write(trips)
                return
            }
        }
        #endif
        do { trips = try JSONDecoder().decode([Trip].self, from: Data(contentsOf: file)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {}
        catch { notice = "تعذّر فتح الرحلات المحفوظة." }
    }

    private func write(_ values: [Trip]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: file, options: [.atomic, .completeFileProtection])
    }

    func save(_ trip: Trip) throws {
        var next = trips
        if let i = next.firstIndex(where: { $0.id == trip.id }) { next[i] = trip }
        else { next.append(trip) }
        try write(next)
        trips = next
    }

    func remove(_ id: UUID) throws {
        let next = trips.filter { $0.id != id }
        try write(next)
        trips = next
    }

    func current(at date: Date) -> Trip? {
        trips.filter { $0.visible(at: date) }.min { $0.expected < $1.expected }
    }

    func refresh(at now: Date, force: Bool = false) async {
        guard !fetching, let t = current(at: now), let number = t.lookupNumber,
              let key = FlightCredential.current else { return }
        let interval: TimeInterval = t.ticketDue(at: now) ? 300 : 3600
        if !force && now.timeIntervalSince(attempted[t.id] ?? t.flight.refreshedAt) < interval { return }
        fetching = true
        attempted[t.id] = now
        defer { fetching = false }
        do {
            let result = try await AeroDataBoxClient(apiKey: key).lookup(flightNumber: number, dateLocal: t.departureDay)
            let options = result.filter { $0.originCode == t.flight.originCode && $0.destinationCode == t.flight.destinationCode && $0.scheduledDepartureUTC != nil }
            guard let match = options.first(where: { $0.id == t.flight.id }) ?? (options.count == 1 ? options.first : nil) else {
                failedRefreshTrip = t.id
                return
            }
            guard var latest = trips.first(where: { $0.id == t.id }),
                  latest.flight.id == t.flight.id, latest.lookupNumber == number,
                  latest.departureDay == t.departureDay else { return }
            latest.flight = match
            try save(latest)
            failedRefreshTrip = nil
        } catch {
            if !Task.isCancelled { failedRefreshTrip = t.id }
        }
    }

    #if DEBUG
    private static func sample(_ mode: String) -> Trip {
        let departure = Date().addingTimeInterval(mode == "-test-upcoming" ? 2 * 86400 : (mode == "-test-delayed" ? -900 : 2 * 3600 + 24 * 60))
        let f = FlightData(flightNumber: "SV 1021", originCode: "RUH", originName: "الرياض",
                           destinationCode: "JED", destinationName: "جدة",
                           scheduledDepartureUTC: departure,
                           scheduledArrivalUTC: departure.addingTimeInterval(6300),
                           revisedDepartureUTC: mode == "-test-delayed" ? departure.addingTimeInterval(3600) : nil,
                           originTimeZone: "Asia/Riyadh", destinationTimeZone: "Asia/Riyadh", status: "Expected",
                           departureTerminal: "5", departureGate: "A12")
        return Trip(flight: f, booking: "K7Q2LA", seat: "8A", lookupNumber: "SV1021",
                    departureDay: ClockText.string(departure, "yyyy-MM-dd", zone: TimeZone(identifier: "Asia/Riyadh")!, arabic: false))
    }
    #endif
}
