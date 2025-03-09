import SwiftUI

struct CodeModificationView: View {
    @Binding var codeContent: String
    @Binding var selectedModel: OllamaModel?
    @State private var modifiedCode: String
    @State private var chatMessage: String = ""
    @State private var chatResponses: [ChatMessage] = []
    @State private var isThinking: Bool = false
    @AppStorage("ollamaServerURL") private var serverURL = "http://localhost:11434"
    @Environment(\.dismiss) private var dismiss
    
    init(codeContent: Binding<String>, selectedModel: Binding<OllamaModel?>) {
        self._codeContent = codeContent
        self._selectedModel = selectedModel
        self._modifiedCode = State(initialValue: codeContent.wrappedValue)
    }
    
    var body: some View {
        HSplitView {
            // Code Editor
            VStack {
                Text("Original Code")
                    .font(.headline)
                TextEditor(text: .constant(codeContent))
                    .font(.system(size: 14, design: .monospaced))
                    .padding()
                
                Text("Modified Code")
                    .font(.headline)
                TextEditor(text: $modifiedCode)
                    .font(.system(size: 14, design: .monospaced))
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Chat Interface
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(chatResponses) { response in
                                MessageBubble(message: response.content, isUser: response.isUser)
                                    .id(response.id)
                                    .contextMenu {
                                        if response.content.contains("```") {
                                            Button("Apply Code Changes") {
                                                extractAndApplyCode(from: response.content)
                                            }
                                        }
                                    }
                            }
                            
                            if isThinking {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                    Text("🤡 RON is Thinking..Like a Clown..")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatResponses) { oldValue, newValue in
                        withAnimation {
                            if let last = chatResponses.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                HStack {
                    TextField("Ask about the code...", text: $chatMessage)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            sendChatMessage()
                        }
                    
                    Button("Send") {
                        sendChatMessage()
                    }
                    .disabled(selectedModel == nil)
                }
                .padding()
            }
            .frame(width: 300)
        }
        .navigationTitle("AI Code Modification")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Model", selection: $selectedModel) {
                    Text("Select Model").tag(nil as OllamaModel?)
                    ForEach(selectedModel != nil ? [selectedModel!] : [], id: \.self) { model in
                        Text(model.name).tag(model as OllamaModel?)
                    }
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button("Modify Code") {
                    requestCodeModification()
                }
                .disabled(selectedModel == nil)
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Changes") {
                    codeContent = modifiedCode
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
    
    private func sendChatMessage() {
        guard let model = selectedModel, !chatMessage.isEmpty else { return }
        
        let userMessage = chatMessage
        chatResponses.append(ChatMessage(content: userMessage, isUser: true))
        
        let prompt = """
        Code Context:
        \(modifiedCode)
        
        Question:
        \(userMessage)
        """
        
        isThinking = true
        chatMessage = ""
        
        NetworkManager.shared.sendMessage(
            prompt,
            serverURL: serverURL,
            model: model.name
        ) { result in
            isThinking = false
            switch result {
            case .success(let response):
                chatResponses.append(ChatMessage(content: response, isUser: false))
            case .failure(let error):
                let errorMessage = NetworkManager.shared.handleNetworkError(error)
                chatResponses.append(ChatMessage(content: errorMessage, isUser: false))
            }
        }
    }
    
    private func requestCodeModification() {
        guard let model = selectedModel else { return }
        
        let prompt = """
        Please analyze and improve this code:
        ```
        \(modifiedCode)
        ```
        
        Provide your response in this format:
        1. First, explain what changes you suggest and why
        2. Then, show the complete improved code between ```
        """
        
        isThinking = true
        chatResponses.append(ChatMessage(
            content: "Please analyze and suggest improvements for this code.",
            isUser: true
        ))
        
        NetworkManager.shared.sendMessage(
            prompt,
            serverURL: serverURL,
            model: model.name
        ) { result in
            isThinking = false
            switch result {
            case .success(let response):
                // Split response into explanation and code
                if let codeStart = response.range(of: "```"),
                   let codeEnd = response.range(of: "```", range: codeStart.upperBound..<response.endIndex) {
                    let explanation = String(response[..<codeStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let code = String(response[codeStart.upperBound..<codeEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Add explanation to chat
                    chatResponses.append(ChatMessage(
                        content: explanation,
                        isUser: false
                    ))
                    
                    // Show suggested changes
                    chatResponses.append(ChatMessage(
                        content: "Suggested code changes:\n```\n\(code)\n```",
                        isUser: false
                    ))
                    
                    // Update modified code
                    modifiedCode = code
                } else {
                    modifiedCode = response
                    chatResponses.append(ChatMessage(
                        content: "Code has been modified. You can review the changes in the editor.",
                        isUser: false
                    ))
                }
            case .failure(let error):
                let errorMessage = NetworkManager.shared.handleNetworkError(error)
                chatResponses.append(ChatMessage(content: errorMessage, isUser: false))
            }
        }
    }
    
    private func extractAndApplyCode(from message: String) {
        if let codeStart = message.range(of: "```"),
           let codeEnd = message.range(of: "```", range: codeStart.upperBound..<message.endIndex) {
            let code = String(message[codeStart.upperBound..<codeEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            modifiedCode = code
        }
    }
} 