import SwiftUI
import UniformTypeIdentifiers

struct CodeEditorView: View {
    @AppStorage("ollamaServerURL") private var serverURL = "http://localhost:11434"
    @State private var projectURL: URL?
    @State private var selectedFile: URL?
    @State private var fileContent: String = ""
    @State private var isEditing: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showFileCreator: Bool = false
    @State private var newFileName: String = ""
    @State private var errorMessage: String = ""
    @State private var models: [OllamaModel] = []
    @State private var selectedModel: OllamaModel?
    @State private var showingServerConfig = false
    @State private var showChatWindow = false
    @State private var showModificationWindow = false
    @State private var showDocumentImporter: Bool = false
    
    var body: some View {
        NavigationSplitView {
            // File Browser
            List {
                if let projectURL = projectURL {
                    FileBrowserView(
                        url: projectURL,
                        selectedFile: $selectedFile,
                        fileContent: $fileContent,
                        isEditing: $isEditing,
                        errorMessage: $errorMessage
                    )
                }
            }
        } detail: {
            // Code Editor
            VStack {
                // Add model selection and settings
                HStack {
                    Picker("Model", selection: $selectedModel) {
                        Text("Select Model").tag(nil as OllamaModel?)
                        ForEach(models) { model in
                            Text(model.name).tag(model as OllamaModel?)
                        }
                    }
                    .frame(width: 200)
                    
                    Button(action: { showingServerConfig.toggle() }) {
                        Image(systemName: "gear")
                    }
                }
                .padding()
                
                if selectedFile != nil {
                    TextEditor(text: $fileContent)
                        .font(.system(size: 14, design: .monospaced))
                        .padding()
                        .onChange(of: fileContent) { oldValue, newValue in
                            isEditing = true
                        }
                    
                    if isEditing {
                        HStack {
                            Button("Save") {
                                saveFile()
                            }
                            .padding()
                            
                            Button("Ask AI to Modify") {
                                showModificationWindow = true
                            }
                            .padding()
                            
                            Button("Ask AI About Code") {
                                showChatWindow = true
                            }
                            .padding()
                            
                            Button("Attach Document") {
                                showDocumentImporter = true
                            }
                            .padding()
                        }
                    }
                } else {
                    Text("Select a file to edit")
                        .foregroundColor(.secondary)
                }
            }
            .sheet(isPresented: $showingServerConfig) {
                ServerConfigView(serverURL: $serverURL, models: $models)
            }
            .sheet(isPresented: $showChatWindow) {
                NavigationStack {
                    CodeChatView(codeContent: $fileContent, selectedModel: $selectedModel)
                }
            }
            .sheet(isPresented: $showModificationWindow) {
                NavigationStack {
                    CodeModificationView(codeContent: $fileContent, selectedModel: $selectedModel)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showFileImporter = true
                }) {
                    Label("Open Project", systemImage: "folder")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showFileCreator = true
                }) {
                    Label("New File", systemImage: "plus")
                }
            }
        }
        .onAppear {
            refreshModels()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporterResult(result)
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleDocumentImporterResult(result)
        }
        .alert("Create New File", isPresented: $showFileCreator) {
            TextField("File name", text: $newFileName)
            Button("Create", action: createNewFile)
            Button("Cancel", role: .cancel) { }
        }
        .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
            Button("OK", role: .cancel) {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            if let url = urls.first {
                projectURL = url
                selectedFile = nil
                fileContent = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func handleDocumentImporterResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            if let url = urls.first {
                // Read the document content and process it
                let documentContent = try String(contentsOf: url)
                // Here you can implement logic to send the document content to the AI
                print("Document content: \(documentContent)") // For debugging
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func createNewFile() {
        guard let projectURL = projectURL, !newFileName.isEmpty else { return }
        
        let fileURL = projectURL.appendingPathComponent(newFileName)
        
        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
            selectedFile = fileURL
            fileContent = ""
            newFileName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func saveFile() {
        guard let selectedFile = selectedFile else { return }
        
        do {
            try fileContent.write(to: selectedFile, atomically: true, encoding: .utf8)
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func modifyWithAI() {
        guard selectedFile != nil else { return }
        
        // Send the file content to AI for modification
        let prompt = "Please review and improve this code:\n\(fileContent)"
        
        NetworkManager.shared.sendMessage(
            prompt,
            serverURL: serverURL,
            model: selectedModel?.name ?? "codellama"
        ) { result in
            switch result {
            case .success(let response):
                fileContent = response
            case .failure(let error):
                errorMessage = NetworkManager.shared.handleNetworkError(error)
            }
        }
    }
    
    private func refreshModels() {
        NetworkManager.shared.getModels(serverURL: serverURL) { result in
            switch result {
            case .success(let models):
                self.models = models
                selectedModel = models.first
            case .failure(let error):
                errorMessage = NetworkManager.shared.handleNetworkError(error)
            }
        }
    }
}

struct FileBrowserView: View {
    let url: URL
    @Binding var selectedFile: URL?
    @Binding var fileContent: String
    @Binding var isEditing: Bool
    @Binding var errorMessage: String
    
    var body: some View {
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            ForEach(contents, id: \.self) { item in
                if item.hasDirectoryPath {
                    DisclosureGroup(item.lastPathComponent) {
                        FileBrowserView(
                            url: item,
                            selectedFile: $selectedFile,
                            fileContent: $fileContent,
                            isEditing: $isEditing,
                            errorMessage: $errorMessage
                        )
                    }
                } else {
                    Button(action: {
                        selectedFile = item
                        loadFileContent(item)
                    }) {
                        Text(item.lastPathComponent)
                            .foregroundColor(selectedFile == item ? .accentColor : .primary)
                    }
                }
            }
        }
    }
    
    private func loadFileContent(_ url: URL) {
        do {
            let content = try String(contentsOf: url)
            fileContent = content
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
} 
