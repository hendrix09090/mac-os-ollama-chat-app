import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
}
 
struct CodeChatView: View { 
    @Binding var codeContent: String
    @Binding var selectedModel: OllamaModel?
    @State private var chatMessage: String = ""
    @State private var chatResponses: [ChatMessage] = []
    @State private var isThinking: Bool = false
    @State private var showingCodePreview = false
    @State private var proposedCode: String = ""
    @AppStorage("ollamaServerURL") private var serverURL = "http://localhost:11434"
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
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
                                            extractAndPreviewCode(from: response.content)
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
                .onChange(of: isThinking) { oldValue, newValue in
                    withAnimation {
                        if isThinking {
                            proxy.scrollTo("thinking", anchor: .bottom)
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
                
                Menu {
                    Button("Ask Question") {
                        sendChatMessage()
                    }
                    Button("Fix Code") {
                        requestCodeFix()
                    }
                    Button("Generate New Code") {
                        requestNewCode()
                    }
                } label: {
                    Text("Send")
                }
                .disabled(selectedModel == nil || chatMessage.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Code Chat")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Model", selection: $selectedModel) {
                    Text("Select Model").tag(nil as OllamaModel?)
                    ForEach(selectedModel != nil ? [selectedModel!] : [], id: \.self) { model in
                        Text(model.name).tag(model as OllamaModel?)
                    }
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingCodePreview) {
            NavigationStack {
                CodePreviewView(
                    originalCode: codeContent,
                    proposedCode: proposedCode,
                    onApply: {
                        codeContent = proposedCode
                        dismiss()
                    }
                )
            }
        }
    }
    
    private func extractAndPreviewCode(from message: String) {
        if let codeStart = message.range(of: "```"),
           let codeEnd = message.range(of: "```", range: codeStart.upperBound..<message.endIndex) {
            proposedCode = String(message[codeStart.upperBound..<codeEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            showingCodePreview = true
        }
    }
    
    private func requestCodeFix() {
        let prompt = """
        Please fix any issues in this code and explain the changes:
        ```
        \(codeContent)
        ```
        
        Provide your response in this format:
        1. Explain the issues found and fixes applied
        2. Show the complete fixed code between ```
        """
        
        sendAIRequest(prompt: prompt)
    }
    
    private func requestNewCode() {
        let prompt = """
        Based on this request: \(chatMessage)
        
        Please generate code that fits with the current context:
        ```
        \(codeContent)
        ```
        
        Provide your response in this format:
        1. Explain the implementation
        2. Show the complete code between ```
        """
        
        sendAIRequest(prompt: prompt)
    }
    
    private func sendChatMessage() {
        let prompt = """
        Code Context:
        ```
        \(codeContent)
        ```
        
        Question:
        \(chatMessage)
        """
        
        sendAIRequest(prompt: prompt)
    }
    
    private func sendAIRequest(prompt: String) {
        guard let model = selectedModel, !chatMessage.isEmpty else { return }
        
        let userMessage = chatMessage
        chatResponses.append(ChatMessage(content: userMessage, isUser: true))
        chatMessage = ""
        isThinking = true
        
        NetworkManager.shared.sendMessage(
            prompt,
            serverURL: serverURL,
            model: model.name
        ) { result in
            isThinking = false
            switch result {
            case .success(let response):
                chatResponses.append(ChatMessage(content: response, isUser: false))
                
                // If response contains code blocks, add an "Apply Changes" button to the message
                if response.contains("```") {
                    DispatchQueue.main.async {
                        if let codeStart = response.range(of: "```"),
                           let codeEnd = response.range(of: "```", range: codeStart.upperBound..<response.endIndex) {
                            let code = String(response[codeStart.upperBound..<codeEnd.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            proposedCode = code
                        }
                    }
                }
            case .failure(let error):
                let errorMessage = NetworkManager.shared.handleNetworkError(error)
                chatResponses.append(ChatMessage(content: errorMessage, isUser: false))
            }
        }
    }
}

struct CodePreviewView: View {
    let originalCode: String
    let proposedCode: String
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            CodeDiffView(original: originalCode, modified: proposedCode)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Apply Changes") {
                    onApply()
                }
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .navigationTitle("Code Changes")
        .frame(minWidth: 800, minHeight: 600)
    }
}

enum AppTheme: String, CaseIterable {
    case yellow = "Yellow"
    case dark = "Dark"
    case blue = "Blue"
    case green = "Green"
    case red = "Red"
    case purple = "Purple"
    case orange = "Orange"
    case teal = "Teal"
    case pink = "Pink"
    case brown = "Brown"

    var color: Color {
        switch self {
        case .yellow:
            return Color.yellow.opacity(0.1)
        case .dark:
            return Color.black
        case .blue:
            return Color.blue.opacity(0.1)
        case .green:
            return Color.green.opacity(0.1)
        case .red:
            return Color.red.opacity(0.1)
        case .purple:
            return Color.purple.opacity(0.1)
        case .orange:
            return Color.orange.opacity(0.1)
        case .teal:
            return Color.teal.opacity(0.1)
        case .pink:
            return Color.pink.opacity(0.1)
        case .brown:
            return Color.brown.opacity(0.1)
        }
    }
} 