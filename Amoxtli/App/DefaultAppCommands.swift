import SwiftUI

struct DefaultAppCommands: Commands {
    let flow: DefaultAppFlow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Establecer como app predeterminada para Markdown…") {
                Task { await flow.setAsDefaultFromMenu() }
            }
        }
    }
}
