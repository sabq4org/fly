import SwiftUI
import Security

enum FlightCredential {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "net.alialhazmi.Iqlaa.AeroDataBox",
         kSecAttrAccount as String: "personal-api"]
    }

    static var current: String? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func store(_ key: String) throws {
        let value = [kSecValueData as String: Data(key.utf8)]
        let result = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        var item = query.merging(value) { _, new in new }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
    }
}

struct ConnectionSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error = ""
    let saved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("مفتاح API", text: $value)
                        .environment(\.layoutDirection, .leftToRight)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("AeroDataBox")
                } footer: {
                    Text(FlightCredential.current == nil
                         ? "انسخ المفتاح من حسابك لجلب الرحلات وتحديث مواعيدها. يُحفظ في سلسلة مفاتيح هذا الآيفون."
                         : "يوجد مفتاح محفوظ على هذا الجهاز. أدخل مفتاحًا جديدًا إذا أردت استبداله.")
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("ربط بيانات الرحلات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        do {
                            try FlightCredential.store(value.trimmingCharacters(in: .whitespacesAndNewlines))
                            saved()
                            dismiss()
                        } catch { self.error = "تعذّر حفظ المفتاح على الجهاز." }
                    }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
