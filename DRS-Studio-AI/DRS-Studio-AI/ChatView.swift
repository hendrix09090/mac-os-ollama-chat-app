import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import PDFKit // Import PDFKit for PDF handling

// Document Context Management
struct DocumentContext {
    let content: String
    let keyThemes: [String]
    let documentType: DocumentType
    var chapterCount: Int = 0  // Track number of chapters
    
    enum DocumentType {
        case story
        case technical
        case academic
        case business
        case other
        
        var defaultSections: [String] {
            switch self {
            case .story:
                return ["Opening Scene", "Character Development", "Plot Development", "Rising Action", "Climax/Resolution"]
            case .technical:
                return ["Overview", "Technical Background", "Implementation Details", "Examples", "Conclusion"]
            case .academic:
                return ["Abstract", "Introduction", "Methodology", "Results", "Discussion", "Conclusion"]
            case .business:
                return ["Executive Summary", "Market Analysis", "Strategy", "Implementation", "Financial Projections"]
            case .other:
                return ["Introduction", "Main Content", "Supporting Details", "Conclusion"]
            }
        }
    }
}

enum AppTheme: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case blue = "Blue"
    case green = "Green"
    case red = "Red"

    var color: Color {
        switch self {
        case .light:
            return Color.white
        case .dark:
            return Color.black
        case .blue:
            return Color.blue.opacity(0.1)
        case .green:
            return Color.green.opacity(0.1)
        case .red:
            return Color.red.opacity(0.1)
        }
    }
}

struct ChatView: View {
    // Add Message struct for unique identification
    struct Message: Identifiable, Hashable {
        let id = UUID()
        let content: String
        let timestamp: Date
        let isUser: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: Message, rhs: Message) -> Bool {
            lhs.id == rhs.id
        }
    }

    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .light
    @AppStorage("ollamaServerURL") private var serverURL = "http://localhost:11434"
    @AppStorage("bingSearchEnabled") private var bingSearchEnabled = false
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var responses: [Message] = []
    @State private var models: [OllamaModel] = []
    @State private var selectedModel: OllamaModel?
    @State private var showingServerConfig = false
    @State private var isThinking = false
    @State private var showDocumentImporter = false
    @State private var currentDocumentContext: DocumentContext?
    @State private var isGeneratingChapter = false
    @State private var lastGeneratedChapterNumber: Int = 0
    @State private var isServerConnected = false
    @State private var showConnectionAlert = false
    @State private var connectionError: String?
    @State private var retryCount = 0
    @State private var shouldStopGeneration = false
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    
    var body: some View {
        VStack {
            // Theme Picker
            HStack {
                Picker("Select Theme", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                // Add Bing Search Toggle
                Toggle(isOn: $bingSearchEnabled) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Bing Search")
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.horizontal)
            }
            .padding()
            
            // Background Color
            ZStack {
                selectedTheme.color
                    .edgesIgnoringSafeArea(.all)

                VStack {
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
                        
                        // Add server status indicator
                        Circle()
                            .fill(isServerConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                    }
                    .padding()
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(responses) { message in
                                    MessageBubble(message: message.content, isUser: message.isUser)
                                        .id(message.id)
                                }
                                
                                if isThinking {
                                    HStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                        Text("🤡 RON is Thinking..Like a Clown..")
                                            .foregroundColor(.red)
                                        Spacer()
                                        Button(action: {
                                            shouldStopGeneration = true
                                            isThinking = false
                                            responses.append(Message(
                                                content: "🛑 AI response generation stopped by user",
                                                timestamp: Date(),
                                                isUser: false
                                            ))
                                        }) {
                                            Label("Stop", systemImage: "stop.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding()
                                    .id("thinking")
                                }
                            }
                        }
                        .onChange(of: responses) { oldValue, newValue in
                            withAnimation {
                                if let last = responses.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                } else if isThinking {
                                    proxy.scrollTo("thinking", anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: isThinking) { oldValue, newValue in
                            withAnimation {
                                if isThinking {
                                    proxy.scrollTo("thinking", anchor: .bottom)
                                } else if let last = responses.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Enter message", text: $message)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                if !message.isEmpty && selectedModel != nil {
                                    sendMessage()
                                }
                            }
                        
                        // Add Attach Document Button
                        Button("Attach Document") {
                            showDocumentImporter = true
                        }
                        .padding(.leading, 8) // Add some spacing

                        Button("Send") {
                            sendMessage()
                        }
                        .disabled(selectedModel == nil)

                        // Add Clear Chat Button
                        Button("Clear Chat") {
                            clearChat()
                        }
                        .padding(.leading, 8) // Add some spacing

                        // Add Generate Chapter Button
                        if currentDocumentContext != nil {
                            Button("Generate Chapter") {
                                generateNewChapter()
                            }
                            .padding(.leading, 8)
                            .disabled(isGeneratingChapter)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingServerConfig) {
            ServerConfigView(serverURL: $serverURL, models: $models)
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleDocumentImporterResult(result)
        }
        .alert("Connection Error", isPresented: $showConnectionAlert) {
            Button("Retry") {
                retryCount = 0
                checkServerConnection()
            }
            Button("Settings") {
                showingServerConfig = true
            }
        } message: {
            Text(connectionError ?? "Unable to connect to Ollama server")
        }
        .onAppear {
            checkServerConnection()
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600) // Set minimum window size
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Quit")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .background(WindowAccessor())
        #endif
    }
    
    private func checkServerConnection() {
        isServerConnected = false
        NetworkManager.shared.getModels(serverURL: serverURL) { result in
            switch result {
            case .success(let models):
                self.models = models
                selectedModel = models.first
                isServerConnected = true
                showConnectionAlert = false
                connectionError = nil
                retryCount = 0
            case .failure(let error):
                handleConnectionError(error)
            }
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        isServerConnected = false
        let errorMessage = NetworkManager.shared.handleNetworkError(error)
        connectionError = errorMessage
        
        if retryCount < maxRetries {
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                checkServerConnection()
            }
        } else {
            showConnectionAlert = true
        }
        
        responses.append(Message(
            content: "⚠️ Connection Error: \(errorMessage)\nRetrying... (\(retryCount)/\(maxRetries))",
            timestamp: Date(),
            isUser: false
        ))
    }
    
    private func sendMessageWithRetry() {
        guard let model = selectedModel else { return }
        
        shouldStopGeneration = false
        
        func attemptSend(retryCount: Int = 0) {
            guard !shouldStopGeneration else {
                isThinking = false
                return
            }
            
            NetworkManager.shared.sendMessage(
                message,
                serverURL: serverURL,
                model: model.name
            ) { result in
                guard !shouldStopGeneration else {
                    isThinking = false
                    return
                }
                
                isThinking = false
                switch result {
                case .success(let response):
                    processAndAddAIResponse(response)
                    message = ""
                case .failure(let error):
                    if retryCount < maxRetries {
                        // Retry with exponential backoff
                        let delay = retryDelay * pow(2, Double(retryCount))
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            guard !shouldStopGeneration else { return }
                            attemptSend(retryCount: retryCount + 1)
                        }
                        responses.append(Message(
                            content: "⚠️ Connection error. Retrying in \(Int(delay)) seconds... (\(retryCount + 1)/\(maxRetries))",
                            timestamp: Date(),
                            isUser: false
                        ))
                    } else {
                        let errorMessage = NetworkManager.shared.handleNetworkError(error)
                        responses.append(Message(
                            content: "❌ Failed to send message after \(maxRetries) attempts: \(errorMessage)",
                            timestamp: Date(),
                            isUser: false
                        ))
                        showConnectionAlert = true
                    }
                }
            }
        }
        
        responses.append(Message(content: message, timestamp: Date(), isUser: true))
        isThinking = true
        attemptSend()
    }
    
    public func sendMessage() {
        guard !message.isEmpty, selectedModel != nil else { return }
        
        if !isServerConnected {
            checkServerConnection()
            responses.append(Message(
                content: "⚠️ Checking server connection before sending message...",
                timestamp: Date(),
                isUser: false
            ))
            return
        }
        
        sendMessageWithRetry()
    }

    public func clearChat() {
        responses.removeAll()
    }

    private func handleDocumentImporterResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            if let url = urls.first {
                let fileExtension = url.pathExtension.lowercased()
                var documentContent: String?

                switch fileExtension {
                case "txt":
                    // Read TXT files
                    documentContent = try String(contentsOf: url, encoding: .utf8)
                    
                case "pdf":
                    // Read PDF files
                    if let pdfDocument = PDFDocument(url: url) {
                        documentContent = pdfDocument.string // Extract text from PDF
                    } else {
                        responses.append(Message(content: "❌ Error reading PDF: The file could not be opened.", timestamp: Date(), isUser: false))
                    }
                    
                case "docx":
                    // Read DOCX files
                    documentContent = try readDocxFile(url: url)
                    
                case "doc":
                    // Read DOC files
                    documentContent = try readDocFile(url: url)
                    
                default:
                    responses.append(Message(content: "❌ Error: Unsupported file format. Please use TXT, PDF, DOCX, or DOC files.", timestamp: Date(), isUser: false))
                    return
                }

                if let content = documentContent {
                    responses.append(Message(content: "📎 Document loaded successfully. Analyzing content...", timestamp: Date(), isUser: false))
                    print("Document content: \(content)") // For debugging
                    
                    // Send the document content to the AI for analysis
                    sendDocumentContentToAI(content)
                }
            }
        } catch {
            responses.append(Message(content: "❌ Error reading document: \(error.localizedDescription)", timestamp: Date(), isUser: false))
            print("Error reading document: \(error.localizedDescription)")
        }
    }

    private func readDocxFile(url: URL) throws -> String {
        // For now, we'll use a simple approach to extract text from DOCX
        // This is a temporary solution until we implement a proper DOCX reader
        do {
            let fileData = try Data(contentsOf: url)
            // Convert the data to a string, removing any non-text content
            if let text = String(data: fileData, encoding: .utf8) {
                // Clean up the text by removing any XML/binary content
                return text.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            } else {
                throw NSError(domain: "DocxReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not decode DOCX file content"])
            }
        } catch {
            throw error
        }
    }

    private func readDocFile(url: URL) throws -> String {
        // Implement your DOC reading logic here
        // This is a placeholder; you will need to use a library to extract text from DOC files
        return "DOC content goes here" // Replace with actual content
    }

    private func sendDocumentContentToAI(_ documentContent: String) {
        // Initial analysis to establish document context
        let contextAnalysisPrompt = """
        Please analyze this document to establish its context. Identify:
        1. Document type (story, technical, academic, business, or other)
        2. Key themes and topics (provide as a comma-separated list)
        3. Main subject matter
        
        Document Content:
        \(documentContent)
        
        Format your response as:
        TYPE: [document type]
        THEMES: [theme1, theme2, ...]
        SUBJECT: [main subject]
        """
        
        isThinking = true
        NetworkManager.shared.sendMessage(
            contextAnalysisPrompt,
            serverURL: serverURL,
            model: selectedModel?.name ?? "codellama"
        ) { result in
            switch result {
            case .success(let contextResponse):
                // Parse the context response and store it
                self.processContextResponse(contextResponse, originalContent: documentContent)
                
                // Now proceed with detailed analysis using the established context
                self.performDetailedAnalysis(documentContent)
            case .failure(let error):
                isThinking = false
                let errorMessage = NetworkManager.shared.handleNetworkError(error)
                responses.append(Message(content: "❌ Error analyzing document context: \(errorMessage)", timestamp: Date(), isUser: false))
            }
        }
    }
    
    private func processContextResponse(_ response: String, originalContent: String) {
        // Extract document type and themes from the response
        let lines = response.components(separatedBy: .newlines)
        var documentType: DocumentContext.DocumentType = .other
        var themes: [String] = []
        
        for line in lines {
            if line.starts(with: "TYPE:") {
                let typeStr = line.replacingOccurrences(of: "TYPE:", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                documentType = {
                    switch typeStr {
                    case "story": return .story
                    case "technical": return .technical
                    case "academic": return .academic
                    case "business": return .business
                    default: return .other
                    }
                }()
            } else if line.starts(with: "THEMES:") {
                themes = line.replacingOccurrences(of: "THEMES:", with: "")
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        
        // Store the context
        currentDocumentContext = DocumentContext(
            content: originalContent,
            keyThemes: themes,
            documentType: documentType
        )
    }
    
    private func performDetailedAnalysis(_ documentContent: String) {
        guard let context = currentDocumentContext else { return }
        
        // Prepare analysis prompt based on document type
        let analysisPrompt = """
        Context-Aware Document Analysis
        Document Type: \(context.documentType)
        Key Themes: \(context.keyThemes.joined(separator: ", "))
        
        Please provide a comprehensive analysis of this document, maintaining strict relevance to its context and themes:

        1. Document Analysis:
           - Summarize the main points in the context of \(context.keyThemes.joined(separator: ", "))
           - Analyze how the identified themes develop throughout the document
           - Evaluate the writing style and tone in relation to the document type
           - Identify the target audience based on content and presentation

        2. Content Structure:
           - Analyze the current organization in relation to \(context.documentType) standards
           - Suggest structural improvements while maintaining the document's purpose
           - Identify areas for expansion within the established themes

        3. Contextual Generation Options:
           Based on this document's specific context:
           \(getContextualSuggestions(for: context.documentType))

        4. Theme-Specific Suggestions:
           For each key theme identified (\(context.keyThemes.joined(separator: ", "))):
           - Potential expansions that maintain thematic consistency
           - Related subtopics that could be explored
           - Supporting elements that could enhance the main themes

        Document Content:
        \(documentContent)

        Please format your response with clear sections using markdown.
        For any generated content or examples, use content blocks (---) or code blocks (```) as appropriate.
        Ensure all suggestions and analysis maintain strict relevance to the document's context and themes.
        """
        
        NetworkManager.shared.sendMessage(
            analysisPrompt,
            serverURL: serverURL,
            model: selectedModel?.name ?? "codellama"
        ) { result in
            isThinking = false
            switch result {
            case .success(let response):
                // Process and add the response
                processAndAddAIResponse(response)
                
                // Add contextual generation options
                if let context = self.currentDocumentContext {
                    responses.append(Message(content: self.getContextualGenerationPrompt(for: context), timestamp: Date(), isUser: false))
                }
            case .failure(let error):
                let errorMessage = NetworkManager.shared.handleNetworkError(error)
                responses.append(Message(content: "❌ Error analyzing document: \(errorMessage)", timestamp: Date(), isUser: false))
            }
        }
    }
    
    private func getContextualSuggestions(for documentType: DocumentContext.DocumentType) -> String {
        switch documentType {
        case .story:
            return """
                - Character development opportunities
                - Plot expansion possibilities
                - World-building elements
                - Narrative perspective variations
            """
        case .technical:
            return """
                - Technical detail elaboration
                - Implementation examples
                - Use case scenarios
                - Architecture considerations
            """
        case .academic:
            return """
                - Research expansion areas
                - Methodology details
                - Literature connections
                - Theoretical frameworks
            """
        case .business:
            return """
                - Market analysis depth
                - Strategic considerations
                - Implementation steps
                - Risk assessments
            """
        case .other:
            return """
                - Content expansion areas
                - Supporting details
                - Related topics
                - Practical applications
            """
        }
    }
    
    private func getContextualGenerationPrompt(for context: DocumentContext) -> String {
        let basePrompt = """
            📚 Based on your document's themes (\(context.keyThemes.joined(separator: ", "))), I can help you generate:
            
            1. Contextual Expansions:
            """
        
        let specificOptions = switch context.documentType {
        case .story:
            """
               - New chapters continuing the current narrative
               - Character backstories
               - World-building details
               - Alternative plot developments
            """
        case .technical:
            """
               - Additional technical sections
               - Implementation guides
               - Example scenarios
               - Architecture details
            """
        case .academic:
            """
               - Literature review sections
               - Methodology details
               - Research implications
               - Theoretical frameworks
            """
        case .business:
            """
               - Market analysis sections
               - Strategy recommendations
               - Implementation plans
               - Risk assessment details
            """
        case .other:
            """
               - Related content sections
               - Supporting materials
               - Practical applications
               - Detailed examples
            """
        }
        
        return """
        \(basePrompt)
        \(specificOptions)
        
        2. Theme-Specific Content:
        \(context.keyThemes.map { "   - Expansions related to '\($0)'" }.joined(separator: "\n"))
        
        3. Supporting Elements:
           - Additional context and background
           - Related examples and illustrations
           - Connected topics within the same domain
        
        Just specify which type of content you'd like me to generate, and I'll ensure it matches your document's context and themes!
        """
    }

    // Helper function to process and split AI responses
    private func processAndAddAIResponse(_ response: String) {
        // Update the function to use Message struct
        func addResponse(_ content: String) {
            responses.append(Message(content: content, timestamp: Date(), isUser: false))
        }

        // Split response by code blocks and content blocks
        let codeBlockPattern = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
        let contentBlockPattern = try? NSRegularExpression(pattern: "---[\\s\\S]*?---", options: [])
        let chapterPattern = try? NSRegularExpression(pattern: "Chapter [\\d]+:[\\s\\S]*?(?=Chapter [\\d]+:|$)", options: [])
        
        // Find all blocks
        let range = NSRange(response.startIndex..., in: response)
        let codeMatches = codeBlockPattern?.matches(in: response, options: [], range: range) ?? []
        let contentMatches = contentBlockPattern?.matches(in: response, options: [], range: range) ?? []
        let chapterMatches = chapterPattern?.matches(in: response, options: [], range: range) ?? []
        
        if codeMatches.isEmpty && contentMatches.isEmpty && chapterMatches.isEmpty {
            // If no special blocks, add the response as is
            let formattedResponse = bingSearchEnabled ?
                """
                🌐 (Internet-Enabled Response)
                
                \(response)
                
                ---
                Note: This response was generated using real-time internet access.
                """ :
                response
            
            addResponse("📄 \(formattedResponse)")
        } else {
            var allBlocks: [(NSRange, BlockType)] = []
            
            // Collect all blocks with their types
            for match in codeMatches {
                allBlocks.append((match.range, .code))
            }
            for match in contentMatches {
                allBlocks.append((match.range, .content))
            }
            for match in chapterMatches {
                allBlocks.append((match.range, .chapter))
            }
            
            // Sort blocks by their location in the text
            allBlocks.sort { $0.0.location < $1.0.location }
            
            // Add initial text if any
            if let firstBlock = allBlocks.first {
                let initialRange = NSRange(location: 0, length: firstBlock.0.location)
                if let initialTextRange = Range(initialRange, in: response) {
                    let initialText = String(response[initialTextRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !initialText.isEmpty {
                        addResponse("📄 Analysis:\n\(initialText)")
                    }
                }
            }
            
            // Process each block
            for (blockRange, blockType) in allBlocks {
                if let textRange = Range(blockRange, in: response) {
                    let blockContent = String(response[textRange])
                    switch blockType {
                    case .code:
                        addResponse("💻 Code Example:\n\(blockContent)")
                    case .content:
                        addResponse("📝 Content Section:\n\(blockContent)")
                    case .chapter:
                        addResponse("📖 Generated Chapter:\n\(blockContent)")
                    }
                }
            }
            
            // Add remaining text if any
            if let lastBlock = allBlocks.last {
                let remainingRange = NSRange(
                    location: lastBlock.0.location + lastBlock.0.length,
                    length: response.count - (lastBlock.0.location + lastBlock.0.length)
                )
                if let remainingTextRange = Range(remainingRange, in: response) {
                    let remainingText = String(response[remainingTextRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remainingText.isEmpty {
                        addResponse("📄 Additional Notes:\n\(remainingText)")
                    }
                }
            }
        }
    }

    // Enum to identify different types of content blocks
    private enum BlockType {
        case code
        case content
        case chapter
    }

    private func generateNewChapter() {
        guard var context = currentDocumentContext else { return }
        
        shouldStopGeneration = false
        context.chapterCount += 1
        lastGeneratedChapterNumber = context.chapterCount
        currentDocumentContext = context
        
        isGeneratingChapter = true
        isThinking = true
        
        let sectionTemplate = context.documentType.defaultSections
            .map { "- " + $0 }
            .joined(separator: "\n")
        
        let chapterPrompt = """
        Based on the following document context, generate Chapter \(context.chapterCount) that maintains the same:
        - Writing style and tone
        - Theme consistency
        - Character voices (if applicable)
        - World-building elements
        - Technical depth (for technical documents)
        
        Document Type: \(context.documentType)
        Key Themes: \(context.keyThemes.joined(separator: ", "))
        
        Chapter Structure:
        Please organize the chapter using these sections:
        \(sectionTemplate)
        
        Guidelines:
        1. Start with "Chapter \(context.chapterCount):" followed by a compelling title
        2. Include all sections listed above, maintaining document type appropriate formatting
        3. Maintain consistent terminology and concepts
        4. Follow the established narrative or technical style
        5. Build upon existing themes: \(context.keyThemes.joined(separator: ", "))
        6. Ensure continuity with the original content
        7. Match the complexity level of the original document
        
        Original Content Summary:
        \(context.content.prefix(500))...
        
        Please generate Chapter \(context.chapterCount) that seamlessly extends this content while maintaining its core characteristics.
        Format the chapter with clear section headings and appropriate transitions between sections.
        """
        
        NetworkManager.shared.sendMessage(
            chapterPrompt,
            serverURL: serverURL,
            model: selectedModel?.name ?? "codellama"
        ) { result in
            isGeneratingChapter = false
            isThinking = false
            
            switch result {
            case .success(let response):
                // Format the chapter response
                let formattedChapter = """
                📖 Generated Chapter \(self.lastGeneratedChapterNumber):
                
                \(response)
                
                ---
                Chapter generated based on:
                - Document Type: \(context.documentType)
                - Themes: \(context.keyThemes.joined(separator: ", "))
                - Sections: \(context.documentType.defaultSections.joined(separator: " → "))
                """
                responses.append(Message(content: formattedChapter, timestamp: Date(), isUser: false))
                
            case .failure(let error):
                let errorMessage = NetworkManager.shared.handleNetworkError(error)
                responses.append(Message(content: "❌ Error generating chapter: \(errorMessage)", timestamp: Date(), isUser: false))
            }
        }
    }
}

#if os(macOS)
// Helper view to configure window properties
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

// Add this clipboard helper
struct Clipboard {
    static func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// Update the MessageBubble view
struct MessageBubble: View {
    let message: String
    let isUser: Bool
    @State private var showCopiedToast = false
    @State private var selectedText: String?
    
    var body: some View {
        HStack {
            if isUser {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .textSelection(.enabled) // Enable text selection
                    .foregroundColor(isUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isUser ? Color.blue : Color.green)
                    )
                    .contextMenu {
                        Button {
                            Clipboard.copyToClipboard(message)
                            showCopiedToast = true
                            
                            // Hide the toast after 1.5 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopiedToast = false
                                }
                            }
                        } label: {
                            Label("Copy Entire Message", systemImage: "doc.on.doc")
                        }
                        
                        // Add a divider for visual separation
                        Divider()
                        
                        // Add help text
                        Text("Tip: You can also select and copy specific text")
                    }
            }
            .overlay(
                Group {
                    if showCopiedToast {
                        ToastView(message: "Copied to clipboard!")
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                },
                alignment: .top
            )
            
            if !isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// Add a custom Toast View for better visual feedback
struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
            )
            .padding(.top, -30) // Position above the message
    }
} 
