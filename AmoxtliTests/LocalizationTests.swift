import XCTest
@testable import Amoxtli

final class LocalizationTests: XCTestCase {
    private let languages = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"]

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
        return try XCTUnwrap(Bundle(path: path), language)
    }

    func testAppShipsEverySupportedLanguage() {
        XCTAssertEqual(Set(Bundle.main.localizations).intersection(languages), Set(languages))
    }

    func testEveryLanguageTranslatesTheSourceText() throws {
        for language in languages where language != "es" {
            let translated = try bundle(for: language).localizedString(forKey: "Abrir enlace", value: nil, table: nil)
            XCTAssertNotEqual(translated, "Abrir enlace", language)
        }
    }

    func testRecentItemsAndSettingsAreTranslated() throws {
        let keys = [
            "Abrir recientes",
            "Borrar historial",
            "No se encontró «%@»",
            "Puede que se haya movido o eliminado. Se quitó de los recientes.",
            "Abrir el último archivo o carpeta al iniciar",
            "Si ya no existe, se muestra la ventana de bienvenida.",
            "Archivos y carpetas recientes",
        ]
        for language in languages where language != "es" {
            let bundle = try bundle(for: language)
            for key in keys {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key, "\(language): \(key)")
            }
        }
    }

    func testSpanishTranslatesTheOneEnglishKey() throws {
        let translated = try bundle(for: "es").localizedString(forKey: "Open Folder…", value: nil, table: nil)
        XCTAssertEqual(translated, "Abrir carpeta…")
    }
}
