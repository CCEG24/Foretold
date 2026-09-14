//
//  GameInput.swift
//  Foretold
//
//  A platform-neutral snapshot of a single input event. The scene's input
//  handlers consume only this — never NSEvent (mac) or a DOM event (web) —
//  so the ~500 lines of overlay-priority dispatch in GameScene are shared
//  verbatim across both targets. Each platform supplies a thin adapter that
//  fills the relevant fields:
//
//    • mac  — built from NSEvent (see GameScene's responder overrides)
//    • web  — built from browser pointer/keyboard/wheel events (later)
//
//  Coordinates are already converted to SCENE space by the adapter, and the
//  key code uses the macOS keyCode convention so the existing keybind storage
//  (UserDefaults / localStorage) stays byte-compatible across platforms.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct GameInput {
    /// Click/hover point in scene coordinates (SpriteKit y-up), pre-converted
    /// by the platform adapter. Unused by keyboard events.
    var location: CGPoint = .zero
    /// macOS-convention hardware key code (e.g. 0x31 = Space). The web adapter
    /// maps DOM `KeyboardEvent.code` into this space. Unused by pointer events.
    var keyCode: UInt16 = 0
    /// Event time in seconds, used for double-tap windows (restart, start-run).
    var timestamp: TimeInterval = 0
    /// Vertical scroll delta (wheel events only), in the AppKit sense: positive
    /// scrolls content one way, negative the other. `naturalScrolling` in the
    /// scene decides the final direction.
    var scrollDeltaY: CGFloat = 0
}
