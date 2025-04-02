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

enum ChatTheme: String, CaseIterable {
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

    @AppStorage("selectedTheme") private var selectedTheme: ChatTheme = .yellow
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
        VStack(spacing: 0) {
            // Modern Header with Gradient
            VStack(spacing: 12) {
                HStack {
                    Text("DRS Studio AI")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Theme Picker with modern styling
                    Picker("Select Theme", selection: $selectedTheme) {
                        ForEach(ChatTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    
                    // Web Search Toggle with modern styling
                    Toggle(isOn: $bingSearchEnabled) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                            Text("Web Search")
                        }
                        .foregroundColor(.black)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // Model Selection and Server Status
                HStack(spacing: 16) {
                    // Model Picker with modern styling
                    Picker("Model", selection: $selectedModel) {
                        Text("Select Model").tag(nil as OllamaModel?)
                        ForEach(models) { model in
                            Text(model.name).tag(model as OllamaModel?)
                        }
                    }
                    .frame(width: 200)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    
                    // Server Settings Button
                    Button(action: { showingServerConfig.toggle() }) {
                        Image(systemName: "gear")
                            .foregroundColor(.black)
                            .padding(8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    // Server Status Indicator with animation
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isServerConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 1)
                            )
                        Text(isServerConnected ? "Connected" : "Disconnected")
                            .foregroundColor(.black)
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // Chat Area with modern styling
            ZStack {
                selectedTheme.color
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(responses) { message in
                                    MessageBubble(message: message.content, isUser: message.isUser)
                                        .id(message.id)
                                }
                                
                                if isThinking {
                                    HStack(spacing: 12) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
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
                                                .padding(8)
                                                .background(Color.white.opacity(0.2))
                                                .cornerRadius(8)
                                        }
                                    }
                                    .padding()
                                    .id("thinking")
                                }
                            }
                            .padding(.vertical)
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
                    
                    // Modern Input Area
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            TextField("Enter message", text: $message)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(12)
                                .foregroundColor(.black)
                                .onSubmit {
                                    if !message.isEmpty && selectedModel != nil {
                                        sendMessage()
                                    }
                                }
                            
                            // Action Buttons
                            HStack(spacing: 8) {
                                Button(action: { showDocumentImporter = true }) {
                                    Image(systemName: "doc.badge.plus")
                                        .foregroundColor(.black)
                                        .padding(8)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(8)
                                }
                                
                                Button(action: sendMessage) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.black)
                                        .padding(8)
                                        .background(Color.blue.opacity(0.8))
                                        .cornerRadius(8)
                                }
                                .disabled(selectedModel == nil)
                                
                                Button(action: clearChat) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.black)
                                        .padding(8)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(8)
                                }
                                
                                if currentDocumentContext != nil {
                                    Button(action: generateNewChapter) {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundColor(.black)
                                            .padding(8)
                                            .background(Color.white.opacity(0.2))
                                            .cornerRadius(8)
                                    }
                                    .disabled(isGeneratingChapter)
                                }
                            }
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
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
        
        // Validate server URL
        guard let baseURL = URL(string: serverURL) else {
            handleConnectionError(NSError(domain: "Network", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]))
            return
        }
        
        // Create URLRequest with timeout
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10 // 10 second timeout
        
        // Create URLSession with custom configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.handleConnectionError(error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.handleConnectionError(NSError(domain: "Network", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                self.handleConnectionError(NSError(domain: "HTTP", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"]))
                return
            }
            
            guard let data = data else {
                self.handleConnectionError(NSError(domain: "Data", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.models = response.models
                    self.selectedModel = response.models.first
                    self.isServerConnected = true
                    self.showConnectionAlert = false
                    self.connectionError = nil
                    self.retryCount = 0
                }
            } catch {
                self.handleConnectionError(error)
            }
        }.resume()
    }
    
    private func handleConnectionError(_ error: Error) {
        DispatchQueue.main.async {
            self.isServerConnected = false
            let errorMessage = self.getNetworkErrorDescription(error)
            self.connectionError = errorMessage
            
            if self.retryCount < self.maxRetries {
                self.retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) {
                    self.checkServerConnection()
                }
            } else {
                self.showConnectionAlert = true
            }
            
            self.responses.append(Message(
                content: "⚠️ Connection Error: \(errorMessage)\nRetrying... (\(self.retryCount)/\(self.maxRetries))",
                timestamp: Date(),
                isUser: false
            ))
        }
    }
    
    private func getNetworkErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection"
        case NSURLErrorTimedOut:
            return "Connection timed out"
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server"
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost"
        case NSURLErrorBadURL:
            return "Invalid server URL"
        default:
            return nsError.localizedDescription
        }
    }
    
    private func performWebSearch(query: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(NSError(domain: "WebSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid search query"])))
            return
        }
        
        // Try Wikipedia API first
        let wikipediaURL = "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encodedQuery)&utf8=&format=json"
        performSearchWithURL(wikipediaURL, timeout: 10, isWikipedia: true) { result in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                // If Wikipedia fails, wait a bit before trying DuckDuckGo
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    // Try DuckDuckGo API next
                    let duckDuckGoURL = "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json"
                    self.performSearchWithURL(duckDuckGoURL, timeout: 8, isWikipedia: false) { result in
                        switch result {
                        case .success(let response):
                            completion(.success(response))
                        case .failure(let error):
                            // If DuckDuckGo fails too, wait before trying Google
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                // If both fail, try Google search as last resort
                                let googleURL = "https://www.google.com/search?q=\(encodedQuery)"
                                self.performSearchWithURL(googleURL, timeout: 15, isWikipedia: false) { result in
                                    switch result {
                                    case .success(let response):
                                        completion(.success(response))
                                    case .failure(let error):
                                        // If all fail, return a more descriptive error
                                        let errorMessage = "Web search failed: \(error.localizedDescription)"
                                        completion(.failure(NSError(domain: "WebSearch", code: 12, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func performSearchWithURL(_ urlString: String, timeout: TimeInterval, isWikipedia: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "WebSearch", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Create URLRequest with timeout and additional headers
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("DRS-Studio-AI/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Create URLSession with custom configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 1.5
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1
        config.httpShouldUsePipelining = false // Disable pipelining for better compatibility
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: request) { data, response, error in
            // Process the response before invalidating the session
            let result: Result<String, Error>
            
            if let error = error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain {
                    switch nsError.code {
                    case NSURLErrorNotConnectedToInternet:
                        result = .failure(NSError(domain: "WebSearch", code: 9, userInfo: [NSLocalizedDescriptionKey: "No internet connection available"]))
                    case NSURLErrorTimedOut:
                        result = .failure(NSError(domain: "WebSearch", code: 10, userInfo: [NSLocalizedDescriptionKey: "Request timed out. Please try again."]))
                    case NSURLErrorCannotConnectToHost:
                        result = .failure(NSError(domain: "WebSearch", code: 11, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to search service. Please check your internet connection."]))
                    default:
                        result = .failure(error)
                    }
                } else {
                    result = .failure(error)
                }
            } else if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    if let data = data {
                        if isWikipedia {
                            // Handle Wikipedia JSON response
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let query = json["query"] as? [String: Any],
                               let search = query["search"] as? [[String: Any]] {
                                var results: [String] = []
                                
                                for (index, item) in search.prefix(5).enumerated() {
                                    if let title = item["title"] as? String,
                                       let snippet = item["snippet"] as? String {
                                        // Clean up the snippet by removing HTML tags
                                        let cleanSnippet = snippet
                                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                            .replacingOccurrences(of: "&nbsp;", with: " ")
                                            .replacingOccurrences(of: "&amp;", with: "&")
                                        
                                        results.append("\(index + 1). **\(title)**: \(cleanSnippet)")
                                    }
                                }
                                
                                if results.isEmpty {
                                    result = .failure(NSError(domain: "WebSearch", code: 5, userInfo: [NSLocalizedDescriptionKey: "No results found"]))
                                } else {
                                    result = .success("🔍 Wikipedia Search Results:\n\n\(results.joined(separator: "\n\n"))")
                                }
                            } else {
                                result = .failure(NSError(domain: "WebSearch", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Wikipedia response"]))
                            }
                        } else if urlString.contains("duckduckgo.com") {
                            // Handle DuckDuckGo JSON response
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                var results: [String] = []
                                
                                // Add abstract if available
                                if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
                                    results.append("Abstract: \(abstract)")
                                }
                                
                                // Add related topics if available
                                if let relatedTopics = json["RelatedTopics"] as? [[String: Any]] {
                                    for topic in relatedTopics {
                                        if let text = topic["Text"] as? String {
                                            results.append(text)
                                        }
                                    }
                                }
                                
                                if results.isEmpty {
                                    result = .failure(NSError(domain: "WebSearch", code: 5, userInfo: [NSLocalizedDescriptionKey: "No results found"]))
                                } else {
                                    result = .success("🔍 Search Results:\n\n\(results.joined(separator: "\n\n"))\n\nSource: DuckDuckGo")
                                }
                            } else {
                                result = .failure(NSError(domain: "WebSearch", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to parse DuckDuckGo response"]))
                            }
                        } else {
                            // Handle Google HTML response
                            if let htmlString = String(data: data, encoding: .utf8) {
                                let results = self.extractGoogleSearchResults(from: htmlString)
                                if results.isEmpty {
                                    result = .failure(NSError(domain: "WebSearch", code: 7, userInfo: [NSLocalizedDescriptionKey: "No results found"]))
                                } else {
                                    result = .success("🔍 Search Results:\n\n\(results)\n\nSource: Google Search")
                                }
                            } else {
                                result = .failure(NSError(domain: "WebSearch", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Google response"]))
                            }
                        }
                    } else {
                        result = .failure(NSError(domain: "WebSearch", code: 4, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                    }
                } else if httpResponse.statusCode == 429 {
                    // Handle rate limiting
                    result = .failure(NSError(domain: "WebSearch", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded. Please wait a moment and try again."]))
                } else {
                    result = .failure(NSError(domain: "WebSearch", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"]))
                }
            } else {
                result = .failure(NSError(domain: "WebSearch", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }
            
            // Now that we've processed everything, invalidate the session
            session.invalidateAndCancel()
            
            // Call completion on the main thread
            DispatchQueue.main.async {
                completion(result)
            }
        }
        task.resume()
    }
    
    private func extractGoogleSearchResults(from html: String) -> String {
        // Basic pattern to extract search results
        let pattern = "<div class=\"BNeawe vvjwJb AP7Wnd\".*?>(.*?)</div>"
        var results: [String] = []
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range(at: 1),
                   let range = Range(matchRange, in: html) {
                    let result = String(html[range])
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "&nbsp;", with: " ")
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !result.isEmpty && !results.contains(result) {
                        results.append(result)
                    }
                }
            }
        }
        
        return results.prefix(5).enumerated().map { index, result in
            "\(index + 1). \(result)"
        }.joined(separator: "\n\n")
    }

    private func sendMessage() {
        guard !message.isEmpty, selectedModel != nil else { return }
        
        // Store the message and clear the input field immediately
        let userMessage = message
        message = ""
        
        // Add user's message to responses immediately
        responses.append(Message(content: userMessage, timestamp: Date(), isUser: true))
        
        if !isServerConnected {
            checkServerConnection()
            responses.append(Message(
                content: "⚠️ Checking server connection before sending message...",
                timestamp: Date(),
                isUser: false
            ))
            return
        }
        
        if bingSearchEnabled {
            // Perform web search first
            isThinking = true
            
            performWebSearch(query: userMessage) { result in
                switch result {
                case .success(let searchResults):
                    // Append search results to the message
                    let augmentedMessage = """
                    🌐 Web Search Results:
                    \(searchResults)
                    
                    Original Query:
                    \(userMessage)
                    """
                    
                    self.sendMessageWithRetry(message: augmentedMessage)
                    
                case .failure(let error):
                    self.isThinking = false
                    self.responses.append(Message(
                        content: "❌ Web search failed: \(error.localizedDescription)",
                        timestamp: Date(),
                        isUser: false
                    ))
                }
            }
        } else {
            // Regular message sending without web search
            sendMessageWithRetry(message: userMessage)
        }
    }

    private func sendMessageWithRetry(message: String, retryCount: Int = 0) {
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
                isThinking = false
                switch result {
                case .success(let response):
                    processAndAddAIResponse(response)
                    
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
        
        isThinking = true
        attemptSend()
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
                    
                case "rtf":
                    // Read RTF files
                    do {
                        let rtfData = try Data(contentsOf: url)
                        if let rtfString = try? NSAttributedString(
                            data: rtfData,
                            options: [.documentType: NSAttributedString.DocumentType.rtf],
                            documentAttributes: nil
                        ) {
                            documentContent = rtfString.string
                        } else {
                            responses.append(Message(content: "❌ Error reading RTF: The file could not be opened.", timestamp: Date(), isUser: false))
                        }
                    } catch {
                        responses.append(Message(content: "❌ Error reading RTF file: \(error.localizedDescription)", timestamp: Date(), isUser: false))
                    }
                    
                case "md", "markdown":
                    // Read Markdown files
                    documentContent = try String(contentsOf: url, encoding: .utf8)
                    
                case "html", "htm":
                    // Read HTML files
                    if let htmlData = try? Data(contentsOf: url),
                       let htmlString = String(data: htmlData, encoding: .utf8) {
                        // Basic HTML to text conversion
                        documentContent = htmlString
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&lt;", with: "<")
                            .replacingOccurrences(of: "&gt;", with: ">")
                            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        responses.append(Message(content: "❌ Error reading HTML: The file could not be opened.", timestamp: Date(), isUser: false))
                    }
                    
                case "json":
                    // Read JSON files
                    if let jsonData = try? Data(contentsOf: url),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                       let jsonString = String(data: prettyData, encoding: .utf8) {
                        documentContent = jsonString
                    } else {
                        responses.append(Message(content: "❌ Error reading JSON: The file could not be opened.", timestamp: Date(), isUser: false))
                    }
                    
                case "csv":
                    // Read CSV files
                    if let csvData = try? Data(contentsOf: url),
                       let csvString = String(data: csvData, encoding: .utf8) {
                        // Convert CSV to readable format
                        let rows = csvString.components(separatedBy: .newlines)
                        documentContent = rows.map { row in
                            row.components(separatedBy: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .joined(separator: " | ")
                        }.joined(separator: "\n")
                    } else {
                        responses.append(Message(content: "❌ Error reading CSV: The file could not be opened.", timestamp: Date(), isUser: false))
                    }
                    
                default:
                    responses.append(Message(content: "❌ Error: Unsupported file format. Please use TXT, PDF, DOCX, DOC, RTF, MD, HTML, JSON, or CSV files.", timestamp: Date(), isUser: false))
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

    // Add a test function to verify DuckDuckGo access
    private func testDuckDuckGoAccess() {
        isThinking = true
        responses.append(Message(
            content: "🔍 Testing DuckDuckGo search access...",
            timestamp: Date(),
            isUser: false
        ))
        
        performWebSearch(query: "test") { result in
            DispatchQueue.main.async {
                self.isThinking = false
                switch result {
                case .success(let searchResults):
                    self.responses.append(Message(
                        content: "✅ DuckDuckGo search is working!\n\nTest Results:\n\(searchResults)",
                        timestamp: Date(),
                        isUser: false
                    ))
                case .failure(let error):
                    self.responses.append(Message(
                        content: "❌ DuckDuckGo search failed: \(error.localizedDescription)",
                        timestamp: Date(),
                        isUser: false
                    ))
                }
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
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    if !isUser {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(message)
                                .foregroundColor(isUser ? .white : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message, forType: .string)
                                showCopiedToast = true
                                
                                // Hide toast after 2 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCopiedToast = false
                                }
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(isUser ? .white.opacity(0.7) : .gray)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(12)
                    .background(isUser ? Color.blue : Color.green.opacity(0.8))
                    .cornerRadius(16)
                    
                    if isUser {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                }
                
                if showCopiedToast {
                    Text("Copied to clipboard")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .transition(.opacity)
                }
            }
            
            if !isUser { Spacer() }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
    }
}

// Add a custom Toast View for better visual feedback
struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .padding(.top, -30)
    }
} 
