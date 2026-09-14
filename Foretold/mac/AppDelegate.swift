//
//  AppDelegate.swift
//  Foretold
//
//  Created by chenyige on 01/09/2026.
//


// macOS host entry point. The web target has its own WASM entry point, so this
// whole file is compiled only where AppKit exists.
#if canImport(AppKit)
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}
#endif
