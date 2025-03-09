//
//  DRS_Studio_AIApp.swift
//  DRS-Studio-AI
//
//  Created by danny on 2025/2/20.
//

import SwiftUI
import SwiftData

@main
struct DRS_Studio_AIApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(sharedModelContainer)
    }
}

struct MainView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
        }
    }
}
