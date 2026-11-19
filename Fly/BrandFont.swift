import SwiftUI
import CoreText

/// خط «سنة الحرف اليدوية» لشعار التطبيق.
/// ملفات الخط (Fly/Fonts/*.otf) خارج المستودع العام لأنها مرخّصة؛ إذا لم توجد يرجع النص لخط النظام.
enum BrandFont {
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("TheYearofHandicrafts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func bold(_ size: CGFloat) -> Font { font("TheYearofHandicrafts-Bold", size, fallback: .bold) }
    static func black(_ size: CGFloat) -> Font { font("TheYearofHandicrafts-Black", size, fallback: .heavy) }

    private static func font(_ name: String, _ size: CGFloat, fallback: Font.Weight) -> Font {
        UIFont(name: name, size: size) != nil ? .custom(name, fixedSize: size) : .system(size: size, weight: fallback)
    }
}
