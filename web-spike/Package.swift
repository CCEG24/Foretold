// swift-tools-version:6.0
//
// De-risk spike: the smallest possible OpenSpriteKit app, built to WASM as a
// WASI reactor and served as a Render static site. Its only job is to prove the
// toolchain chain works BEFORE porting Foretold's real GameScene.
//
// Dependency wiring and linker flags mirror the working reference game
// 1amageek/megaman. OpenSpriteKit is referenced by local path because it in turn
// references its OpenCore* siblings by local path — run ./fetch-deps.sh first to
// populate Deps/.
import PackageDescription

let package = Package(
    name: "HelloScene",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "Deps/OpenSpriteKit"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.50.2"),
    ],
    targets: [
        .executableTarget(
            name: "HelloScene",
            dependencies: [
                .product(name: "OpenSpriteKit", package: "OpenSpriteKit"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            path: "Sources/HelloScene",
            linkerSettings: [
                // Build as a WASI reactor and export the entry points so the JS
                // loader can call setup()/getCanvasWidth()/getCanvasHeight().
                // (These flags are wasm-only; this target is not built natively.)
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
