// swift-tools-version: 6.0
import PackageDescription

// The single source of truth for the manifest.json wire format shared by
// Mullion (client, via MullionCore) and Mullion-Admin. Both sides used to hand-roll
// this shape independently, and every real cross-repo bug traced back to
// that drift (sizeMB actually storing bytes, a leading space in a saved URL
// failing the client's entire decode, compatibility keys doubling as the
// requirements list).
let package = Package(
    name: "MullionManifestKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MullionManifestKit", targets: ["MullionManifestKit"]),
    ],
    targets: [
        .target(name: "MullionManifestKit"),
    ]
)
