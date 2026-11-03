import AppKit

/// AppKit is required here: SwiftUI's `alert` has no checkbox, and it hangs from a view, while this
/// prompt runs at launch, when there may be no window yet.
struct DefaultAppAlerts: DefaultAppPrompting {
    func askToSetAsDefault() -> DefaultAppPromptAnswer {
        let alert = NSAlert()
        alert.messageText = String(localized: "Usar Amoxtli para abrir archivos Markdown")
        alert.informativeText = String(localized: "Los archivos .md y .markdown se abrirán en Amoxtli al hacer doble clic en ellos.")
        alert.addButton(withTitle: String(localized: "Establecer como predeterminada"))
        alert.addButton(withTitle: String(localized: "Ahora no"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "No volver a preguntar")
        let response = alert.runModal()
        return DefaultAppPromptAnswer(
            accepted: response == .alertFirstButtonReturn,
            dontAskAgain: alert.suppressionButton?.state == .on
        )
    }

    func showAlreadyDefault() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Amoxtli ya es tu app predeterminada para Markdown")
        alert.runModal()
    }

    func showFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "No se pudo establecer Amoxtli como predeterminada")
        alert.informativeText = String(localized: "También puedes cambiarlo en Finder: elige un archivo Markdown, abre Obtener información y usa la sección Abrir con.")
        alert.runModal()
    }
}
