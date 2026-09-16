// swift-tools-version:6.0
//
// Foretold web target. Compiles the SAME source the mac app uses (the 7 game-
// logic files + GameInput + KeyValueStore + GameScene, via symlinks under
// Sources/FortoldWeb) against OpenSpriteKit instead of Apple SpriteKit, plus a
// web-only WebMain.swift bootstrap.
//
// OpenSpriteKit + its OpenCore*/swift-webgpu siblings are reused from the spike's
// checkout (../web-spike/Deps) so we don't clone them twice.
import PackageDescription

let package = Package(
    name: "FortoldWeb",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../web-spike/Deps/OpenSpriteKit"),
        // Pinned to the minor we resolved against (Package.resolved: 0.56.1).
        // An open `from:` range lets any 0.x in, so a JavaScriptKit release could
        // change the CI build with no commit here — and 0.56 is where the faster
        // Swift 6.4 bridging landed, so the pairing matters.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", .upToNextMinor(from: "0.56.1")),
    ],
    targets: [
        .executableTarget(
            name: "FortoldWeb",
            dependencies: [
                .product(name: "OpenSpriteKit", package: "OpenSpriteKit"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            path: "Sources/FortoldWeb",
            // Compile in Swift 5 language mode to match how the mac Xcode target
            // builds GameScene. OpenSpriteKit's SKScene/SKView aren't @MainActor
            // like Apple's, so Swift 6 strict-concurrency would flag main-actor
            // access across the shared file; v5 keeps those as warnings.
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xclang-linker", "-mexec-model=reactor",
                    "-Xlinker", "--export=setup",
                    "-Xlinker", "--export=getCanvasWidth",
                    "-Xlinker", "--export=getCanvasHeight",
                ])
            ]
        ),
    ]
)
