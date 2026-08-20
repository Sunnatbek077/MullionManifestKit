//
//  Manifest.swift
//  MullionManifestKit
//
//  The exact JSON shape of manifest.json in Sunnatbek077/mullion-runtime —
//  written by Mullion-Admin, read by Mullion. This package is the only definition
//  of that wire format; neither app may model it independently.
//
//  Evolution rules:
//  - Adding a *field*: give it a tolerant default in init(from:) below, so
//    manifests written before the field existed still decode.
//  - Changing a field's type/meaning, or adding an enum case: bump
//    `currentSchemaVersion`. `Manifest.decode(from:)` refuses payloads newer
//    than it supports, so an outdated app fails with a clear "update
//    required" error instead of silently mis-reading (or, worse for
//    Mullion-Admin, overwriting) data it doesn't understand.
//

import Foundation

public struct Manifest: Codable, Sendable, Equatable {

    /// Bump per the evolution rules in the header comment.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runtimeVersion: String
    public var categories: [Category]
    public var components: [Component]
    public var games: [Game]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = Manifest.currentSchemaVersion,
        runtimeVersion: String,
        categories: [Category],
        components: [Component],
        games: [Game],
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.runtimeVersion = runtimeVersion
        self.categories = categories
        self.components = components
        self.games = games
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Manifests written before schemaVersion existed are all schema 1.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        runtimeVersion = try container.decode(String.self, forKey: .runtimeVersion)
        categories = try container.decode([Category].self, forKey: .categories)
        components = try container.decode([Component].self, forKey: .components)
        games = try container.decode([Game].self, forKey: .games)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Decoding / encoding entry points

public enum ManifestSchemaError: Error, LocalizedError, Sendable {
    /// The payload declares a schema newer than this binary understands.
    /// The only safe reaction is "update the app" — decoding anyway risks
    /// silently dropping data (client) or clobbering it on the next PUT
    /// (Mullion-Admin).
    case unsupportedSchemaVersion(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            "This manifest uses schema v\(found), but this app only supports up to v\(supported). Update the app to continue."
        }
    }
}

extension Manifest {

    /// The one way to decode a manifest payload: probes `schemaVersion`
    /// first (tolerant of any future shape changes around it), gates on it,
    /// then decodes fully.
    public static func decode(from data: Data) throws -> Manifest {
        struct SchemaProbe: Decodable {
            let schemaVersion: Int?
        }
        let probed = try JSONDecoder().decode(SchemaProbe.self, from: data).schemaVersion ?? 1
        guard probed <= currentSchemaVersion else {
            throw ManifestSchemaError.unsupportedSchemaVersion(found: probed, supported: currentSchemaVersion)
        }
        return try decoder().decode(Manifest.self, from: data)
    }

    public func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    /// ISO-8601 dates, matching what `encoder()` writes.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Sorted keys + pretty printing keep manifest.json diffs readable in
    /// the repo's history — that history is the system's only audit trail.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - Category

extension Manifest {
    public struct Category: Identifiable, Sendable, Codable, Hashable {
        public let id: UUID
        public var name: String
        public var icon: String
        public var colorName: CategoryColor

        public init(id: UUID, name: String, icon: String, colorName: CategoryColor) {
            self.id = id
            self.name = name
            self.icon = icon
            self.colorName = colorName
        }

        public enum CategoryColor: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
            case blue, purple, orange, teal, red, green, pink, indigo, brown, mint, cyan, yellow

            public var id: String { rawValue }
        }
    }
}

// MARK: - Component

extension Manifest {
    public struct Component: Identifiable, Sendable, Codable, Hashable {
        public let id: UUID
        public var componentId: String
        public var version: String
        public var description: String
        public var icon: String
        public var categoryId: UUID
        /// Raw byte count of the file. The JSON key is `sizeMB` for
        /// historical reasons — Mullion-Admin always populated it with bytes
        /// (upload API size / Content-Length), and shipped clients already
        /// read it that way, so the *name* is fixed here instead of the wire.
        public var sizeBytes: Int
        public var sha256: String
        public var fileName: String
        public var downloadURL: String
        public var gameCompatibility: [String: CompatibilityLevel]
        public var status: ComponentStatus
        public var updatedAt: Date

        public enum ComponentStatus: String, Sendable, Codable, CaseIterable, Hashable {
            case published = "Published"
            case draft = "Draft"
            case deprecated = "Deprecated"
        }

        private enum CodingKeys: String, CodingKey {
            case id, componentId, version, description, icon, categoryId
            case sizeBytes = "sizeMB"
            case sha256, fileName, downloadURL, gameCompatibility, status, updatedAt
        }

        public init(
            id: UUID,
            componentId: String,
            version: String,
            description: String,
            icon: String,
            categoryId: UUID,
            sizeBytes: Int,
            sha256: String,
            fileName: String,
            downloadURL: String,
            gameCompatibility: [String: CompatibilityLevel],
            status: ComponentStatus,
            updatedAt: Date
        ) {
            self.id = id
            self.componentId = componentId
            self.version = version
            self.description = description
            self.icon = icon
            self.categoryId = categoryId
            self.sizeBytes = sizeBytes
            self.sha256 = sha256
            self.fileName = fileName
            self.downloadURL = downloadURL
            self.gameCompatibility = gameCompatibility
            self.status = status
            self.updatedAt = updatedAt
        }

        /// Custom decode for two hardenings learned in production:
        /// - `downloadURL` is trimmed — a single entry saved with a leading
        ///   space once failed decoding of the *entire* manifest client-side,
        ///   surfacing as a bogus "catalog offline".
        /// - Non-identity fields fall back to defaults instead of failing the
        ///   whole payload over one degraded entry.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            componentId = try container.decode(String.self, forKey: .componentId)
            version = try container.decode(String.self, forKey: .version)
            categoryId = try container.decode(UUID.self, forKey: .categoryId)
            status = try container.decode(ComponentStatus.self, forKey: .status)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)

            description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
            icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "cube.box.fill"
            sizeBytes = try container.decodeIfPresent(Int.self, forKey: .sizeBytes) ?? 0
            sha256 = try container.decodeIfPresent(String.self, forKey: .sha256) ?? ""
            fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
            gameCompatibility = try container.decodeIfPresent([String: CompatibilityLevel].self, forKey: .gameCompatibility) ?? [:]
            downloadURL = (try container.decodeIfPresent(String.self, forKey: .downloadURL) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - Game

extension Manifest {
    public struct Game: Identifiable, Sendable, Codable, Hashable {
        public let id: UUID
        public var name: String
        public var folderName: String
        public var steamId: String
        public var publisher: String
        public var exeFile: String
        public var detectFiles: [String]
        public var requiredComponents: [String]
        public var settings: GameSettings
        public var compatibility: [String: CompatibilityLevel]
        public var wineEnv: [String: String]
        public var dllOverrides: [String: String]
        public var iconURL: String?
        public var status: GameStatus
        public var version: String
        public var publishedAt: Date?
        public var updatedAt: Date

        public enum GameStatus: String, Sendable, Codable, CaseIterable, Hashable {
            case published = "Published"
            case draft = "Draft"
            case archived = "Archived"
        }

        public struct GameSettings: Sendable, Codable, Hashable {
            public var directx: DirectXVersion
            public var windowsVersion: WindowsVersion
            public var multiplayer: Bool
            public var antiCheat: String?

            public init(directx: DirectXVersion, windowsVersion: WindowsVersion, multiplayer: Bool, antiCheat: String?) {
                self.directx = directx
                self.windowsVersion = windowsVersion
                self.multiplayer = multiplayer
                self.antiCheat = antiCheat
            }

            public enum DirectXVersion: String, Sendable, Codable, CaseIterable, Hashable {
                case dx9 = "DX9"
                case dx10 = "DX10"
                case dx11 = "DX11"
                case dx12 = "DX12"
            }

            public enum WindowsVersion: String, Sendable, Codable, CaseIterable, Hashable {
                case win10 = "win10"
                case win11 = "win11"
            }
        }

        public init(
            id: UUID,
            name: String,
            folderName: String,
            steamId: String,
            publisher: String,
            exeFile: String,
            detectFiles: [String],
            requiredComponents: [String],
            settings: GameSettings,
            compatibility: [String: CompatibilityLevel],
            wineEnv: [String: String],
            dllOverrides: [String: String],
            iconURL: String?,
            status: GameStatus,
            version: String,
            publishedAt: Date?,
            updatedAt: Date
        ) {
            self.id = id
            self.name = name
            self.folderName = folderName
            self.steamId = steamId
            self.publisher = publisher
            self.exeFile = exeFile
            self.detectFiles = detectFiles
            self.requiredComponents = requiredComponents
            self.settings = settings
            self.compatibility = compatibility
            self.wineEnv = wineEnv
            self.dllOverrides = dllOverrides
            self.iconURL = iconURL
            self.status = status
            self.version = version
            self.publishedAt = publishedAt
            self.updatedAt = updatedAt
        }

        /// Identity/config fields are strict; list- and metadata-fields fall
        /// back to empty defaults so one sparse entry can't fail the payload.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            folderName = try container.decode(String.self, forKey: .folderName)
            exeFile = try container.decode(String.self, forKey: .exeFile)
            settings = try container.decode(GameSettings.self, forKey: .settings)
            status = try container.decode(GameStatus.self, forKey: .status)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)

            steamId = try container.decodeIfPresent(String.self, forKey: .steamId) ?? ""
            publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
            detectFiles = try container.decodeIfPresent([String].self, forKey: .detectFiles) ?? []
            requiredComponents = try container.decodeIfPresent([String].self, forKey: .requiredComponents) ?? []
            compatibility = try container.decodeIfPresent([String: CompatibilityLevel].self, forKey: .compatibility) ?? [:]
            wineEnv = try container.decodeIfPresent([String: String].self, forKey: .wineEnv) ?? [:]
            dllOverrides = try container.decodeIfPresent([String: String].self, forKey: .dllOverrides) ?? [:]
            iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
            version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
            publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        }
    }
}

// MARK: - CompatibilityLevel

public enum CompatibilityLevel: String, Sendable, Codable, CaseIterable, Hashable {
    case verified = "Verified"
    case partial = "Partial"
    case incompatible = "Incompatible"
    case unknown = "Unknown"

    /// SF Symbol name — semantic data only; mapping onto colors/views is the
    /// UI layer's job on each side.
    public var symbol: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .incompatible: "xmark.seal.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    public var colorName: String {
        switch self {
        case .verified: "green"
        case .partial: "orange"
        case .incompatible: "red"
        case .unknown: "gray"
        }
    }
}
