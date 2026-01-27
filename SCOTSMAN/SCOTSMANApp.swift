//
//  SCOTSMANApp.swift
//  SCOTSMAN
//
//  Created by Ian Miller on 1/27/26.
//

import SwiftUI
import CoreData

@main
struct SCOTSMANApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
