import SwiftUI

struct ServerConfigView: View {
    @Binding var serverURL: String
    @State private var tempServerURL: String = ""
    @Binding var models: [OllamaModel]
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Ollama Server URL", text: $tempServerURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Refresh Models") {
                    refreshModels()
                }
                
                Button("Test Connection") {
                    testConnection()
                }
            }
            .padding()
            .navigationTitle("Server Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        serverURL = tempServerURL
                        dismiss()
                    }
                }
            }
            .alert("Connection Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            tempServerURL = serverURL
        }
    }
    
    private func refreshModels() {
        NetworkManager.shared.getModels(serverURL: tempServerURL) { result in
            switch result {
            case .success(let models):
                self.models = models
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func testConnection() {
        NetworkManager.shared.testServerConnection(serverURL: tempServerURL) { result in
            switch result {
            case .success:
                errorMessage = "Connection successful!"
                showingError = true
            case .failure(let error):
                errorMessage = NetworkManager.shared.handleNetworkError(error)
                showingError = true
            }
        }
    }
} 