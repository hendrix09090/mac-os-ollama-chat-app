import Foundation

struct OllamaModel: Codable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let modified_at: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case modified_at
    }
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
} 