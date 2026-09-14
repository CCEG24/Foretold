//
//  WebCompat.swift
//  Foretold
//
//  Small shims filling gaps between Apple's SpriteKit and OpenSpriteKit, so the
//  shared GameScene compiles unchanged on the web target. Compiled ONLY on the
//  WASM/web build (empty on Apple platforms, where these already exist).

#if !canImport(SpriteKit)
import OpenSpriteKit

extension SKColor {
    /// UIKit/AppKit's `SKColor.withAlphaComponent` isn't provided by OpenSpriteKit.
    /// Its SKColor exposes rgba directly, so reconstruct with the new alpha.
    func withAlphaComponent(_ alpha: CGFloat) -> SKColor {
        SKColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif
