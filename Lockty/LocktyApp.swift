//
//  LocktyApp.swift
//  Lockty
//
//  Created by Gabrisp on 25/08/2026.
//

import SwiftUI

@main
struct LocktyApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
