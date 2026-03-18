//
//  ImageSelectorApp.swift
//  ImageSelector
//
//  Created by Makita Naoki on 2026/03/18.
//

import SwiftUI

@main
struct ImageSelectorApp: App {
    @StateObject private var store = ImageStore()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
