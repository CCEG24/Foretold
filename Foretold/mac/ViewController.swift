//
//  ViewController.swift
//  Foretold
//
//  Created by chenyige on 01/09/2026.
//

import Cocoa
import SpriteKit
import GameplayKit

class ViewController: NSViewController {

    @IBOutlet var skView: SKView!

    private var hasPresentedScene = false

    // Present the scene after the first layout pass rather than in viewDidLoad:
    // at load time the view still has its storyboard size, so presenting there
    // briefly shows the scene stretched into the window's real frame.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !hasPresentedScene, let view = skView else { return }
        hasPresentedScene = true

        // Wider than tall: the board keys off the height, leaving roomy side
        // columns for the reference dropdowns, instructions, and HUD.
        let scene = GameScene(size: CGSize(width: 1680, height: 900))
        scene.scaleMode = .aspectFit
        view.presentScene(scene)

        view.ignoresSiblingOrder = true
        // The FPS / node-count overlays are owned by the scene now, toggled from
        // its settings menu (see GameScene.applyDebugOverlays).
    }

    // SKView forwards mouse and key events to the scene but not the scroll wheel,
    // so hand it down ourselves (the scene scrolls its side dropdowns with it).
    override func scrollWheel(with event: NSEvent) {
        if let scene = skView?.scene as? GameScene {
            scene.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
