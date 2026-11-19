import SwiftUI

private struct Paper: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: 24)
        for x in [rect.minX, rect.maxX] {
            p.addEllipse(in: CGRect(x: x - 8, y: 158, width: 16, height: 16))
        }
        return p
    }
}

struct Ticket: View {
    let trip: Trip
    let now: Date
    let edit: () -> Void
    let refresh: () -> Void
    let refreshMessage: String?
    private var f: FlightData { trip.flight }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("بطاقة الرحلة").font(.subheadline.bold())
                Spacer()
                Text(f.flightNumber).font(.system(.subheadline, design: .monospaced, weight: .semibold))
            }.foregroundStyle(Color.tealInk)
            HStack(spacing: 8) {
                endpoint(f.originCode, f.originName)
                HStack(spacing: 5) {
                    Circle().stroke(lineWidth: 1).frame(width: 5,height: 5)
                    dash
                    Image(systemName: "airplane").font(.body).environment(\.layoutDirection, .leftToRight).rotationEffect(.degrees(180))
                    dash
                    Circle().fill().frame(width: 5,height: 5)
                }.foregroundStyle(Color.tealInk).accessibilityHidden(true)
                endpoint(f.destinationCode, f.destinationName)
            }
            dash.padding(.horizontal, -15).foregroundStyle(.secondary.opacity(0.55))
            HStack(alignment: .top) {
                value("الإقلاع", ClockText.string(trip.expected, "HH:mm", zone: trip.zone), large: true)
                Spacer()
                Text(statusText)
                    .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.tealInk.opacity(0.08), in: Capsule()).foregroundStyle(Color.tealInk)
            }
            if f.status.lowercased() == "delayed" && trip.delayMinutes == 0 {
                Text("تأخرت الرحلة · بانتظار موعد محدث").foregroundStyle(.brown).font(.subheadline).accessibilityIdentifier("delayMessage")
            } else if trip.delayMinutes > 0 && !trip.cancelled {
                Text("تأخير \(trip.delayMinutes) د · الموعد الأصلي " + ClockText.string(trip.scheduled, "HH:mm", zone: trip.zone))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.brown).accessibilityIdentifier("delayMessage")
            }
            HStack(alignment: .top) {
                value("رقم الحجز", trip.booking.isEmpty ? "—" : trip.booking, id: "booking")
                Spacer()
                value("المقعد", trip.seat.isEmpty ? "—" : trip.seat, id: "seat")
                if let gate = f.departureGate { Spacer(); value("البوابة", gate) }
                if let terminal = f.departureTerminal { Spacer(); value("الصالة", terminal) }
            }
            Divider()
            HStack {
                if trip.lookupNumber != nil {
                    Button(action: refresh) {
                        Label("آخر تحديث " + ClockText.string(f.refreshedAt, "HH:mm", zone: trip.zone), systemImage: "arrow.clockwise")
                            .font(.caption)
                    }.accessibilityLabel("تحديث بيانات الرحلة")
                } else { Text("بيانات مدخلة يدويًا").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(action: edit) {
                    Label("تعديل", systemImage: "pencil").font(.subheadline.weight(.semibold))
                }.accessibilityIdentifier("editTrip")
            }
            if let message = refreshMessage, trip.lookupNumber != nil {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 23).padding(.top, 48).padding(.bottom, 20)
            .background { Paper().fill(.white, style: FillStyle(eoFill: true)).clipShape(RoundedRectangle(cornerRadius: 24)) }
            .shadow(color: .ink.opacity(0.055), radius: 10, y: 6)
            .accessibilityElement(children: .contain).accessibilityIdentifier("ticket")
    }

    private var statusText: String {
        if trip.cancelled { return "أُلغيت الرحلة" }
        switch f.status.lowercased() {
        case "boarding": return "بدأ الصعود"
        case "gateclosed": return "البوابة مغلقة"
        case "canceleduncertain": return "إلغاء غير مؤكد"
        default: return ClockText.countdown(trip.expected, now: now)
        }
    }

    private var dash: some View {
        GeometryReader { g in
            Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: g.size.width, y: 0)) }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3,4]))
        }.frame(height: 1)
    }

    private func endpoint(_ code: String?, _ name: String?) -> some View {
        VStack(spacing: 1) {
            Text(code ?? "—").font(.system(size: 33, weight: .semibold, design: .rounded)).tracking(1)
            Text(ClockText.place(code, name)).font(.caption).lineLimit(2)
        }.fixedSize(horizontal: false, vertical: true).frame(minWidth: 68)
    }

    private func value(_ title: String, _ content: String, large: Bool = false, id: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(content).font(.system(size: large ? 26 : 17, weight: .semibold, design: .rounded))
                .monospacedDigit().accessibilityIdentifier(id)
        }
    }
}
