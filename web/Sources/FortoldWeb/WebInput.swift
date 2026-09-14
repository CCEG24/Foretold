//
//  WebInput.swift
//  FortoldWeb — browser input → GameInput adapter (WASM only)
//
//  The mac target feeds GameScene's handle*() methods from NSEvent; here we feed
//  the same methods from DOM pointer/keyboard/wheel events. GameScene's ~500
//  lines of dispatch logic are shared and untouched.

import OpenSpriteKit
import JavaScriptKit

// Closures must outlive this function or JS callbacks fire into freed memory.
// Single-threaded wasm, so unsafe global state is fine.
nonisolated(unsafe) private var retainedClosures: [JSClosure] = []

@MainActor
func installInput(scene: GameScene, canvas: JSObject, width: Double, height: Double) {
    // Browser pointer coords (CSS px, origin top-left) → scene coords
    // (origin bottom-left, y-up). The canvas keeps the 1680×900 aspect (CSS
    // aspect-ratio), so there's no letterbox to correct — just scale + flip Y.
    func scenePoint(_ e: JSObject) -> CGPoint {
        let rect = canvas.getBoundingClientRect!()
        let left = rect.left.number ?? 0
        let top = rect.top.number ?? 0
        let w = rect.width.number ?? width
        let h = rect.height.number ?? height
        let cx = (e.clientX.number ?? 0) - left
        let cy = (e.clientY.number ?? 0) - top
        return CGPoint(x: cx / w * width, y: height - cy / h * height)
    }

    func timestamp(_ e: JSObject) -> TimeInterval { (e.timeStamp.number ?? 0) / 1000.0 }

    let move = JSClosure { args in
        guard let e = args[0].object else { return .undefined }
        scene.handleMouseMoved(GameInput(location: scenePoint(e)))
        return .undefined
    }
    let down = JSClosure { args in
        guard let e = args[0].object else { return .undefined }
        let button = Int(e.button.number ?? 0)
        let input = GameInput(location: scenePoint(e), timestamp: timestamp(e))
        if button == 2 {
            scene.handleRightMouseDown(input)
        } else {
            scene.handleMouseDown(input)
        }
        return .undefined
    }
    let context = JSClosure { args in
        _ = args[0].object?.preventDefault!()   // no browser menu on right-click
        return .undefined
    }
    let wheel = JSClosure { args in
        guard let e = args[0].object else { return .undefined }
        scene.handleScroll(GameInput(scrollDeltaY: CGFloat(e.deltaY.number ?? 0)))
        return .undefined
    }
    let key = JSClosure { args in
        guard let e = args[0].object else { return .undefined }
        guard let code = e.code.string, let mac = domToMacKeyCode[code] else { return .undefined }
        _ = e.preventDefault!()   // stop Space/Tab/arrows from scrolling or moving focus
        scene.handleKeyDown(GameInput(keyCode: mac, timestamp: timestamp(e)))
        return .undefined
    }

    _ = canvas.addEventListener!("pointermove", move)
    _ = canvas.addEventListener!("pointerdown", down)
    _ = canvas.addEventListener!("contextmenu", context)
    _ = canvas.addEventListener!("wheel", wheel)
    _ = JSObject.global.window.object!.addEventListener!("keydown", key)

    retainedClosures = [move, down, context, wheel, key]
}

/// DOM `KeyboardEvent.code` → macOS hardware keyCode, so GameScene's existing
/// keyCode comparisons and the stored keybinds work unchanged on web.
private let domToMacKeyCode: [String: UInt16] = [
    "Space": 0x31, "Enter": 0x24, "Tab": 0x30, "Escape": 0x35, "Backspace": 0x33,
    "Backquote": 0x32,
    "ArrowLeft": 0x7B, "ArrowRight": 0x7C, "ArrowDown": 0x7D, "ArrowUp": 0x7E,
    "KeyA": 0x00, "KeyB": 0x0B, "KeyC": 0x08, "KeyD": 0x02, "KeyE": 0x0E,
    "KeyF": 0x03, "KeyG": 0x05, "KeyH": 0x04, "KeyI": 0x22, "KeyJ": 0x26,
    "KeyK": 0x28, "KeyL": 0x25, "KeyM": 0x2E, "KeyN": 0x2D, "KeyO": 0x1F,
    "KeyP": 0x23, "KeyQ": 0x0C, "KeyR": 0x0F, "KeyS": 0x01, "KeyT": 0x11,
    "KeyU": 0x20, "KeyV": 0x09, "KeyW": 0x0D, "KeyX": 0x07, "KeyY": 0x10, "KeyZ": 0x06,
    "Digit1": 0x12, "Digit2": 0x13, "Digit3": 0x14, "Digit4": 0x15, "Digit5": 0x17,
    "Digit6": 0x16, "Digit7": 0x1A, "Digit8": 0x1C, "Digit9": 0x19, "Digit0": 0x1D,
]
