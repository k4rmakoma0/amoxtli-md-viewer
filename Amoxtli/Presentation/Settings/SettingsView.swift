import SwiftUI

/// Amoxtli > Settings: what opens at launch, and the recent list.
struct SettingsView: View {
    @AppStorage(LaunchPreferences.reopensLastItemKey) private var reopensLastItem = true
    @Environment(RecentItemsModel.self) private var recents

    var body: some View {
        Form {
            Section {
                Toggle("Abrir el último archivo o carpeta al iniciar", isOn: $reopensLastItem)
            } footer: {
                Text("Si ya no existe, se muestra la ventana de bienvenida.")
            }
            // Not `LabeledContent`, which would name the button after its label for VoiceOver.
            Section {
                HStack {
                    Text("Archivos y carpetas recientes")
                    Spacer()
                    Button("Borrar historial", action: recents.clear)
                        .disabled(recents.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 480)
        .fixedSize()
    }
}

#Preview {
    SettingsView()
        .environment(RecentItemsModel())
}
