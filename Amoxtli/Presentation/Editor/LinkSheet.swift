import SwiftUI

/// Asks for the text and destination of a link before inserting it.
struct LinkSheet: View {
    let onInsert: (_ text: String, _ destination: String) -> Void

    @State private var text: String
    @State private var destination: String
    @Environment(\.dismiss) private var dismiss

    init(request: LinkRequest, onInsert: @escaping (_ text: String, _ destination: String) -> Void) {
        self.onInsert = onInsert
        _text = State(initialValue: request.text)
        _destination = State(initialValue: request.destination)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insertar enlace")
                .font(.headline)
            Form {
                TextField("Texto", text: $text, prompt: Text("Texto que se muestra"))
                TextField("Dirección", text: $destination, prompt: Text(verbatim: "https://"))
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insertar", action: insert)
                    .keyboardShortcut(.defaultAction)
                    .disabled(LinkInput.normalized(destination) == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func insert() {
        dismiss()
        onInsert(text, destination)
    }
}

#Preview {
    LinkSheet(request: LinkRequest(text: "Amoxtli", destination: "")) { _, _ in }
}
