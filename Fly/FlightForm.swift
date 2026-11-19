import SwiftUI

struct FlightForm: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    let existing: Trip?

    @State private var manual = false
    @State private var flightNumber = ""
    @State private var originCode = ""
    @State private var destinationCode = ""
    @State private var departureDate = Date().addingTimeInterval(2 * 3600)
    @State private var originTimeZoneID = "Asia/Riyadh"
    @State private var booking = ""
    @State private var seat = ""
    @State private var selectedFlight: FlightData?
    @State private var matches: [FlightData] = []
    @State private var message = ""
    @State private var isLoading = false
    @State private var lookupGeneration = 0
    @State private var confirmDelete = false

    private var hasKey: Bool { FlightCredential.current != nil }
    private var originTimeZone: TimeZone { TimeZone(identifier: originTimeZoneID) ?? .current }
    private var canLookup: Bool {
        !flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasKey
    }

    init(existing: Trip?) {
        self.existing = existing
        _manual = State(initialValue: existing == nil ? FlightCredential.current == nil : existing?.lookupNumber == nil)
        _flightNumber = State(initialValue: existing?.flight.flightNumber ?? "")
        _originCode = State(initialValue: existing?.flight.originCode ?? "")
        _destinationCode = State(initialValue: existing?.flight.destinationCode ?? "")
        _booking = State(initialValue: existing?.booking ?? "")
        _seat = State(initialValue: existing?.seat ?? "")
        let zone = TimeZone(identifier: existing?.flight.originTimeZone ?? "") ?? .current
        _originTimeZoneID = State(initialValue: existing?.flight.originTimeZone ?? (zone.identifier == "GMT" ? "Asia/Riyadh" : zone.identifier))
        _departureDate = State(initialValue: existing?.flight.scheduledDepartureUTC ?? Date().addingTimeInterval(2 * 3600))
        _selectedFlight = State(initialValue: existing?.flight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("رقم الرحلة", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("flightNumber")
                    Picker("طريقة الإدخال", selection: $manual) {
                        Text("جلب بيانات الرحلة").tag(false)
                        Text("إدخال يدوي").tag(true)
                    }
                    .onChange(of: manual) { _, value in
                        invalidateLookup()
                        if !value { selectedFlight = nil; matches = [] }
                    }
                } header: {
                    Text("الرحلة")
                } footer: {
                    if manual {
                        Text("أدخل معلومات الرحلة يدويًا.")
                    } else if !hasKey {
                        Text("لا يوجد مفتاح محفوظ. احفظ المفتاح من إعدادات بيانات الرحلات أو بدّل إلى الإدخال اليدوي.")
                    } else {
                        Text("أدخل الرقم والتاريخ لجلب الرحلة من AeroDataBox.")
                    }
                }

                Section("المسار والموعد") {
                    DatePicker("موعد المغادرة", selection: $departureDate, displayedComponents: manual ? [.date, .hourAndMinute] : [.date])
                        .environment(\.timeZone, originTimeZone)
                    if manual {
                        TextField("مطار المغادرة (IATA)", text: $originCode)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityIdentifier("originCode")
                        TextField("مطار الوصول (IATA)", text: $destinationCode)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityIdentifier("destinationCode")
                        Picker("منطقة وقت المغادرة", selection: $originTimeZoneID) {
                            ForEach(Self.timeZones, id: \.id) { zone in
                                Text(zone.name).tag(zone.id)
                            }
                            ForEach(TimeZone.knownTimeZoneIdentifiers.filter { id in !Self.timeZones.contains { $0.id == id } }, id: \.self) { id in
                                Text(id).tag(id)
                            }
                        }
                        .accessibilityIdentifier("originTimeZone")
                    }
                }

                if !manual {
                    Section {
                        Button {
                            lookup()
                        } label: {
                            HStack {
                                Text(isLoading ? "جارٍ البحث…" : "جلب الرحلات")
                                Spacer()
                                if isLoading { ProgressView() }
                            }
                        }
                        .disabled(!canLookup || isLoading)
                        if !matches.isEmpty {
                            ForEach(matches) { flight in
                                Button {
                                    select(flight)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(flight.originCode ?? "—")  →  \(flight.destinationCode ?? "—")")
                                                .font(.headline).environment(\.layoutDirection, .leftToRight)
                                            Text(ClockText.string(flight.scheduledDepartureUTC ?? Date(), "d MMMM · HH:mm", zone: TimeZone(identifier: flight.originTimeZone ?? "") ?? .current))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedFlight?.id == flight.id { Image(systemName: "checkmark") }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Text("النتائج")
                    }
                }

                Section("بيانات شخصية (اختيارية)") {
                    TextField("رقم الحجز", text: $booking)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("booking")
                    TextField("المقعد", text: $seat)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("seat")
                }

                if !message.isEmpty {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("flightForm")
            .environment(\.layoutDirection, .rightToLeft)
            .navigationTitle(existing == nil ? "إضافة رحلة" : "تعديل الرحلة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                if existing != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("حذف الرحلة", role: .destructive) { confirmDelete = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                        .accessibilityIdentifier("saveTrip")
                        .disabled(!validForSave || isLoading)
                }
            }
            .confirmationDialog("حذف الرحلة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف", role: .destructive) { deleteTrip() }
                Button("إلغاء", role: .cancel) { }
            } message: {
                Text("سيتم حذف الرحلة وبيانات الحجز والمقعد المحفوظة معها.")
            }
            .onChange(of: flightNumber) { _, _ in invalidateLookup() }
            .onChange(of: departureDate) { _, _ in invalidateLookup() }

        }
    }

    private var validForSave: Bool {
        if !manual { return selectedFlight != nil }
        let origin = originCode.cleanedAirportCode
        let destination = destinationCode.cleanedAirportCode
        return origin.count == 3 && destination.count == 3 && origin != destination &&
            origin.allSatisfy { $0.isASCII && $0.isLetter } &&
            destination.allSatisfy { $0.isASCII && $0.isLetter } &&
            !flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let timeZones = [
        (id: "Asia/Riyadh", name: "الرياض (UTC+3)"),
        (id: "Asia/Dubai", name: "دبي (UTC+4)"),
        (id: "Europe/London", name: "لندن"),
        (id: "Europe/Paris", name: "باريس"),
        (id: "Africa/Cairo", name: "القاهرة"),
        (id: "America/New_York", name: "نيويورك"),
        (id: "America/Los_Angeles", name: "لوس أنجلوس")
    ]

    private func invalidateLookup() {
        lookupGeneration += 1
        isLoading = false
        selectedFlight = nil
        matches = []
        message = ""
    }

    private func lookup() {
        guard canLookup else { return }
        lookupGeneration += 1
        let generation = lookupGeneration
        isLoading = true
        message = ""
        matches = []
        selectedFlight = nil
        let number = flightNumber.cleanedFlightNumber
        let date = ClockText.string(departureDate, "yyyy-MM-dd", zone: originTimeZone, arabic: false)
        Task {
            do {
                let values = try await AeroDataBoxClient(apiKey: FlightCredential.current ?? "").lookup(flightNumber: number, dateLocal: date)
                guard generation == lookupGeneration else { return }
                let filtered = values.filter { $0.scheduledDepartureUTC != nil }
                matches = filtered.sorted { ($0.scheduledDepartureUTC ?? .distantFuture) < ($1.scheduledDepartureUTC ?? .distantFuture) }
                if matches.isEmpty {
                    message = "لم نجد رحلة مجدولة مطابقة في هذا التاريخ."
                    isLoading = false
                } else {
                    isLoading = false
                    if selectedFlight == nil, matches.count == 1 { select(matches[0]) }
                }
            } catch {
                guard generation == lookupGeneration else { return }
                message = localized(error)
                isLoading = false
            }
        }
    }

    private func select(_ flight: FlightData) {
        selectedFlight = flight
        message = ""
    }

    private func save() {
        let latest = existing.flatMap { old in store.trips.first(where: { $0.id == old.id }) }
        let flight: FlightData
        let lookupNumber: String?
        if !manual {
            guard let selectedFlight else { return }
            if selectedFlight == existing?.flight, let latest {
                flight = latest.flight
            } else {
                flight = selectedFlight
            }
            lookupNumber = flightNumber.cleanedFlightNumber
        } else {
            let number = flightNumber.cleanedFlightNumber
            let origin = originCode.cleanedAirportCode
            let destination = destinationCode.cleanedAirportCode
            flight = FlightData(flightNumber: number, originCode: origin, destinationCode: destination,
                                scheduledDepartureUTC: departureDate, originTimeZone: originTimeZoneID,
                                status: "Expected")
            lookupNumber = nil
        }
        let day = ClockText.string(flight.scheduledDepartureUTC ?? departureDate, "yyyy-MM-dd", zone: TimeZone(identifier: flight.originTimeZone ?? "") ?? originTimeZone, arabic: false)
        let trip = Trip(id: existing?.id ?? UUID(), flight: flight, booking: booking.trimmingCharacters(in: .whitespacesAndNewlines),
                        seat: seat.trimmingCharacters(in: .whitespacesAndNewlines), lookupNumber: lookupNumber, departureDay: day)
        do { try store.save(trip); dismiss() }
        catch { message = "تعذّر حفظ الرحلة على الجهاز." }
    }

    private func deleteTrip() {
        guard let id = existing?.id else { return }
        do { try store.remove(id); dismiss() }
        catch { message = "تعذّر حذف الرحلة على الجهاز." }
    }

    private func localized(_ error: Error) -> String {
        // AeroDataBox may return an empty 204 body; the client then surfaces a
        // decoding error because the endpoint's success range includes 204.
        if error is DecodingError {
            return "لم نجد رحلة بهذا الرقم في التاريخ المحدد."
        }
        if let e = error as? AeroDataBoxClient.ClientError {
            switch e {
            case .httpStatus(204): return "لم نجد رحلة بهذا الرقم في التاريخ المحدد."
            case .httpStatus(401), .httpStatus(403): return "المفتاح غير صالح أو لا يملك اشتراكًا للوصول إلى بيانات الرحلات."
            case .httpStatus(402): return "يتطلب حساب AeroDataBox رصيدًا أو اشتراكًا نشطًا."
            case .httpStatus(429): return "تم تجاوز حد الاشتراك مؤقتًا. حاول لاحقًا أو راجع خطة AeroDataBox."
            default: break
            }
        }
        return "تعذّر جلب الرحلات الآن. تحقق من الاتصال ومفتاح AeroDataBox."
    }
}

private extension String {
    var cleanedFlightNumber: String { replacingOccurrences(of: " ", with: "").uppercased() }
    var cleanedAirportCode: String { trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
}
