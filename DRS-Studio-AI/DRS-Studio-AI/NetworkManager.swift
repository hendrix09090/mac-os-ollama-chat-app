import Foundation

class NetworkManager {
    static let shared = NetworkManager()

    func handleNetworkError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotFindHost:
                return """
                Connection failed despite server running. Try:
                1. Replace 'localhost' with 127.0.0.1 in server URL
                2. In Xcode: Product → Scheme → Edit Scheme → 
                   Check "Allow Network Client Connections"
                3. Disable any VPN or proxy software
                """
            case NSURLErrorTimedOut:
                return "Connection timed out. The server may be unavailable."
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection."
            case NSURLErrorBadURL:
                return "Invalid server URL format. Should be like http://localhost:11434"
            default:
                return "Network error: \(error.localizedDescription)"
            }
        }
        return "Error: \(error.localizedDescription)"
    }
    
    private func sanitizedBaseURL(_ serverURL: String) -> URL? {
        let cleanedURL = serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        
        guard let baseURL = URL(string: cleanedURL) else {
            return nil
        }
        
        return baseURL
    }

    func getModels(serverURL: String, completion: @escaping (Result<[OllamaModel], Error>) -> Void) {
        guard let baseURL = sanitizedBaseURL(serverURL) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL format"])))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/tags")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Network", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "HTTP", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "Data", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
                completion(.success(response.models))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func sendMessage(_ message: String, serverURL: String, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let baseURL = sanitizedBaseURL(serverURL) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL format"])))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": model,
            "prompt": message,
            "stream": false
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Network", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "HTTP", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "Data", code: 0, userInfo: [NSLocalizedDescriptionKey: "No response data received"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let response = json["response"] as? String {
                    completion(.success(response))
                } else {
                    completion(.failure(NSError(domain: "Data", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func testServerConnection(serverURL: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let baseURL = URL(string: serverURL) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL format"])))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Network", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])))
                return
            }
            
            completion(.success((200...299).contains(httpResponse.statusCode)))
        }.resume()
    }
} 
