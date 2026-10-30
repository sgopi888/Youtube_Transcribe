import SwiftUI
import YTScribeCore

@main
struct YTScribeApp: App {
    @StateObject private var store = JobStore()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).environmentObject(store.library).frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        Settings { SettingsView().environmentObject(store) }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: JobStore
    @State private var key = SecretStore.openAIKey() ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            SecureField("OpenAI API key", text: $key)
            TextField("Model", text: store.$model)
            HStack {
                Button("Save key") { saved = SecretStore.saveOpenAIKey(key.trimmingCharacters(in: .whitespacesAndNewlines)) }
                if saved { Text("Saved").foregroundStyle(.secondary) }
            }
        }
        .padding(20).frame(width: 440)
    }
}
