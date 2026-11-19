import Foundation

/// A normalized flight record returned by AeroDataBox.
///
/// Times are represented as `Date` values (UTC internally). The airport time-zone
/// identifiers are Olson/IANA strings such as `Asia/Riyadh`.
public struct FlightData: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let flightNumber: String
    public let originCode: String?
    public let originName: String?
    public let destinationCode: String?
    public let destinationName: String?
    public let scheduledDepartureUTC: Date?
    public let scheduledArrivalUTC: Date?
    public let revisedDepartureUTC: Date?
    public let revisedArrivalUTC: Date?
    public let originTimeZone: String?
    public let destinationTimeZone: String?
    public let status: String
    public let departureTerminal: String?
    public let departureGate: String?
    public let arrivalTerminal: String?
    public let arrivalGate: String?
    public let refreshedAt: Date

    public init(
        id: String? = nil,
        flightNumber: String,
        originCode: String? = nil,
        originName: String? = nil,
        destinationCode: String? = nil,
        destinationName: String? = nil,
        scheduledDepartureUTC: Date? = nil,
        scheduledArrivalUTC: Date? = nil,
        revisedDepartureUTC: Date? = nil,
        revisedArrivalUTC: Date? = nil,
        originTimeZone: String? = nil,
        destinationTimeZone: String? = nil,
        status: String = "Unknown",
        departureTerminal: String? = nil,
        departureGate: String? = nil,
        arrivalTerminal: String? = nil,
        arrivalGate: String? = nil,
        refreshedAt: Date = Date()
    ) {
        self.flightNumber = flightNumber
        self.originCode = originCode
        self.originName = originName
        self.destinationCode = destinationCode
        self.destinationName = destinationName
        self.scheduledDepartureUTC = scheduledDepartureUTC
        self.scheduledArrivalUTC = scheduledArrivalUTC
        self.revisedDepartureUTC = revisedDepartureUTC
        self.revisedArrivalUTC = revisedArrivalUTC
        self.originTimeZone = originTimeZone
        self.destinationTimeZone = destinationTimeZone
        self.status = status
        self.departureTerminal = departureTerminal
        self.departureGate = departureGate
        self.arrivalTerminal = arrivalTerminal
        self.arrivalGate = arrivalGate
        self.refreshedAt = refreshedAt
        self.id = id ?? FlightData.makeID(
            flightNumber: flightNumber,
            scheduledDepartureUTC: scheduledDepartureUTC,
            originCode: originCode,
            destinationCode: destinationCode
        )
    }

    private static func makeID(flightNumber: String, scheduledDepartureUTC: Date?, originCode: String?, destinationCode: String?) -> String {
        let timestamp = scheduledDepartureUTC.map { String(format: "%.0f", $0.timeIntervalSince1970) } ?? "unknown"
        return [flightNumber.uppercased(), timestamp, originCode ?? "", destinationCode ?? ""].joined(separator: "|")
    }
}

public struct AeroDataBoxClient {
    public enum ClientError: Error, LocalizedError {
        case invalidFlightNumber
        case invalidDateLocal
        case invalidURL
        case httpStatus(Int)
        case emptyAPIKey

        public var errorDescription: String? {
            switch self {
            case .invalidFlightNumber: return "Flight number must not be empty."
            case .invalidDateLocal: return "dateLocal must use YYYY-MM-DD."
            case .invalidURL: return "AeroDataBox request URL is invalid."
            case .httpStatus(let status): return "AeroDataBox returned HTTP status \(status)."
            case .emptyAPIKey: return "An AeroDataBox API key is required."
            }
        }
    }

    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    public init(apiKey: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.aerodatabox.com")!) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.emptyAPIKey }
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    /// Looks up flights using the official Direct Gateway endpoint:
    /// `GET /flights/number/{flightNumber}/{dateLocal}`.
    public func lookup(flightNumber: String, dateLocal: String) async throws -> [FlightData] {
        let number = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { throw ClientError.invalidFlightNumber }
        guard dateLocal.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw ClientError.invalidDateLocal
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("flights/number/\(number)/\(dateLocal)"), resolvingAgainstBaseURL: false)
        // The app's dateLocal is the origin/departure calendar date.
        components?.queryItems = [URLQueryItem(name: "dateLocalRole", value: "Departure")]
        guard let url = components?.url else { throw ClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ClientError.invalidURL }
        if httpResponse.statusCode == 204 { return [] }
        guard (200..<300).contains(httpResponse.statusCode) else { throw ClientError.httpStatus(httpResponse.statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { try Self.decodeDate($0) }
        return try decoder.decode([AeroFlight].self, from: data).map(FlightData.init)
    }

    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let value = try decoder.singleValueContainer().decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        for format in ["yyyy-MM-dd HH:mm:ssX", "yyyy-MM-dd HH:mmX"] {
            let legacyFormatter = DateFormatter()
            legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
            legacyFormatter.calendar = Calendar(identifier: .gregorian)
            legacyFormatter.dateFormat = format
            if let date = legacyFormatter.date(from: value) { return date }
        }
        throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO-8601 date: \(value)")
    }
}

private extension FlightData {
    init(_ flight: AeroFlight) {
        self.init(
            flightNumber: flight.number,
            originCode: flight.departure.airport.iata ?? flight.departure.airport.icao,
            originName: flight.departure.airport.name,
            destinationCode: flight.arrival.airport.iata ?? flight.arrival.airport.icao,
            destinationName: flight.arrival.airport.name,
            scheduledDepartureUTC: flight.departure.scheduledTime?.utc,
            scheduledArrivalUTC: flight.arrival.scheduledTime?.utc,
            revisedDepartureUTC: flight.departure.revisedTime?.utc,
            revisedArrivalUTC: flight.arrival.revisedTime?.utc,
            originTimeZone: flight.departure.airport.timeZone,
            destinationTimeZone: flight.arrival.airport.timeZone,
            status: flight.status,
            departureTerminal: flight.departure.terminal,
            departureGate: flight.departure.gate,
            arrivalTerminal: flight.arrival.terminal,
            arrivalGate: flight.arrival.gate,
            refreshedAt: flight.lastUpdatedUtc
        )
    }
}

private struct AeroFlight: Decodable {
    let number: String
    let departure: Movement
    let arrival: Movement
    let status: String
    let lastUpdatedUtc: Date
}

private struct Movement: Decodable {
    let airport: Airport
    let scheduledTime: DatePair?
    let revisedTime: DatePair?
    let terminal: String?
    let gate: String?
}

private struct Airport: Decodable {
    let iata: String?
    let icao: String?
    let name: String
    let timeZone: String?
}

private struct DatePair: Decodable {
    let utc: Date
    let local: String
}
