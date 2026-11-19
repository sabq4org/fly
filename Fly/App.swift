import SwiftUI

@main
struct FlyApp: App {
    @StateObject private var store = TripStore()
    init() { BrandFont.register() }
    var body: some Scene {
        WindowGroup {
            Home()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA@calendar=gregorian;numbers=latn"))
                .preferredColorScheme(.light)
        }
    }
}

private enum Panel: Identifiable {
    case add, settings, edit(Trip)
    var id: String {
        switch self { case .add: "add"; case .settings: "settings"; case .edit(let t): t.id.uuidString }
    }
}

struct Home: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.scenePhase) private var phase
    @State private var panel: Panel?
    @State private var now = Date()
    @State private var keyVersion = 0

    var body: some View {
        GeometryReader { space in
            let trip = store.current(at: now)
            ZStack {
                LinearGradient(stops: [.init(color: Color(red: 0.23, green: 0.55, blue: 0.87), location: 0),
                                       .init(color: Color(red: 0.55, green: 0.77, blue: 0.94), location: 0.42),
                                       .init(color: Color(red: 0.91, green: 0.96, blue: 0.99), location: 1)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "airplane.departure").font(.system(size: 19, weight: .semibold))
                                Text("إقــــلاع").font(BrandFont.bold(28))
                                    .accessibilityLabel("إقلاع")
                            }
                            Spacer()
                            Button { panel = .settings } label: {
                                Image(systemName: "slider.horizontal.3").frame(width: 42, height: 42)
                                    .background(.white.opacity(0.55), in: Circle())
                            }.accessibilityLabel("إعدادات بيانات الرحلات")
                        }.padding(.horizontal, 25)

                        VStack(spacing: 4) {
                            if let t = trip {
                                Text(ClockText.string(t.scheduled, "EEEE، d MMMM", zone: t.zone))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink.opacity(0.78))
                                    .shadow(color: .white.opacity(0.35), radius: 6)
                                Text("رحلتك إلى " + ClockText.place(t.flight.destinationCode, t.flight.destinationName))
                                    .font(.system(size: 36, weight: .bold)).multilineTextAlignment(.center)
                            } else {
                                Text("رحلتك القادمة").font(.system(size: 36, weight: .bold))
                            }
                        }.padding(.horizontal, 16).padding(.top, 24)

                        let planeWidth = min(space.size.width * 0.84, 440)
                        VStack(spacing: -planeWidth * 0.11) {
                            Image("Aircraft").resizable().scaledToFit()
                                .frame(width: planeWidth)
                                .shadow(color: .ink.opacity(0.16), radius: 14, y: 12)
                                .padding(.top, 26)
                                .accessibilityHidden(true).allowsHitTesting(false).zIndex(1)
                            Group {
                                if let t = trip, t.ticketDue(at: now) {
                                    Ticket(trip: t, now: now, edit: { panel = .edit(t) },
                                           refresh: { Task { await store.refresh(at: Date(), force: true) } },
                                           refreshMessage: store.refreshMessage(for: t.id))
                                } else if let t = trip {
                                    VStack(spacing: 12) {
                                        Text(t.flight.flightNumber).font(.title2.bold().monospacedDigit())
                                        Text(ClockText.string(t.scheduled, "d MMMM · h:mm a", zone: t.zone))
                                        Text("تظهر بطاقة رحلتك قبل الإقلاع بخمس ساعات.")
                                            .font(.footnote).foregroundStyle(.secondary)
                                        Button("تعديل الرحلة") { panel = .edit(t) }.accessibilityIdentifier("editTrip")
                                    }.padding(.top, 20).padding(24).frame(maxWidth: .infinity)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 24))
                                        .accessibilityElement(children: .contain).accessibilityIdentifier("summary")
                                } else {
                                    VStack(spacing: 10) {
                                        Text("أضف أول رحلة لك").font(.title3.bold())
                                        Text("اجمع موعد الإقلاع ورقم الحجز والمقعد في بطاقة واحدة.")
                                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                        addButton
                                    }.padding(.top, 18).padding(24).frame(maxWidth: .infinity)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 24))
                                }
                            }.padding(.horizontal, 20)
                        }
                        .background(alignment: .top) {
                            Image("Clouds").resizable().scaledToFit()
                                .frame(width: space.size.width * 1.08)
                                .opacity(0.95)
                                .accessibilityHidden(true).allowsHitTesting(false)
                        }
                        .padding(.top, 6)
                        if trip != nil { addButton.padding(.top, 17) }
                        let later = store.trips.filter { $0.id != trip?.id && $0.visible(at: now) }.sorted { $0.scheduled < $1.scheduled }
                        if !later.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("رحلاتك التالية").font(.headline)
                                ForEach(later) { next in
                                    Button { panel = .edit(next) } label: {
                                        HStack {
                                            Text(ClockText.place(next.flight.destinationCode, next.flight.destinationName))
                                            Spacer()
                                            Text(ClockText.string(next.scheduled, "d MMM · HH:mm", zone: next.zone)).font(.subheadline)
                                            Image(systemName: "chevron.forward").font(.caption)
                                        }
                                    }
                                }
                            }.padding(20).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                                .padding(.horizontal, 20).padding(.top, 16)
                        }
                    }.padding(.top, 4).padding(.bottom, 20)
                    .frame(maxWidth: 550).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(Color.ink)
        .tint(Color.tealInk)
        .sheet(item: $panel) { item in
            switch item {
            case .settings: ConnectionSettings { keyVersion += 1 }
            case .add: FlightForm(existing: nil)
            case .edit(let trip): FlightForm(existing: trip)
            }
        }
        .alert("الرحلات", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("حسنًا") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .task(id: "\(phase)-\(keyVersion)") {
            guard phase == .active else { return }
            while !Task.isCancelled {
                now = Date()
                await store.refresh(at: now)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var addButton: some View {
        Button { panel = .add } label: {
            Label("إضافة رحلة", systemImage: "plus").font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(.white.opacity(0.54), in: Capsule())
        }.accessibilityIdentifier("addFlight")
    }
}

extension Color {
    static let ink = Color(red: 0.07, green: 0.16, blue: 0.23)
    static let tealInk = Color(red: 0.07, green: 0.36, blue: 0.40)
}
