//
//  JarvisApp.swift
//  Jarvis
//
//  Created by rohan on 12/02/26.
//

import SwiftUI
import SwiftData
import MWDATCore

#if DEBUG
import MWDATMockDevice
#endif

@main
struct JarvisApp: App {

    // MARK: - SwiftData Container

    let modelContainer: ModelContainer

    // MARK: - Initialization

    init() {
        // CRITICAL: Configure Meta DAT SDK first
        // This must happen before any SDK usage
        do {
            try Wearables.configure()
            print("[Jarvis] ✅ Meta DAT SDK configured successfully")
        } catch {
            print("[Jarvis] ❌ Meta DAT SDK configuration failed: \(error)")
        }

        // Setup SwiftData with Conversation and Message models
        do {
            let schema = Schema([
                Conversation.self,
                Message.self
            ])

            // Configure storage with optional iCloud sync
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: Constants.Storage.enableiCloudSync ? .automatic : .none
            )

            modelContainer = try ModelContainer(for: schema, configurations: config)
            print("[Jarvis] ✅ SwiftData ModelContainer initialized")

            if Constants.Storage.enableiCloudSync {
                print("[Jarvis] ☁️  iCloud sync enabled")
            }
        } catch {
            fatalError("[Jarvis] ❌ Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            MainAppView()
                .preferredColorScheme(.dark)  // Force dark mode
        }
        .modelContainer(modelContainer)
    }
}
