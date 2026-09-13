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

        view.showsFPS = true
        view.showsNodeCount = true
    }
}
