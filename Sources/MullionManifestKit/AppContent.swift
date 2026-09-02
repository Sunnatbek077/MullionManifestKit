//
//  AppContent.swift
//  MullionManifestKit
//
//  Two documents published alongside `manifest.json` in the same
//  `mullion-runtime` repo, written by Mullion-Admin and read by Mullion:
//
//  - `news.json`       — the client's News tab
//  - `app-config.json` — support and community links
//  - `update.json`     — the newest published build of Mullion itself
//
//  They live here for the same reason `Manifest` does: both sides need the
//  identical shape, and every real cross-repo bug in this system traced back
//  to hand-rolling a shape twice. Adding a field here gets it to both apps at
//  once; adding it in one app gets it to one app and a silent mismatch.
//
//  **They are deliberately separate files from the manifest, and from each
//  other.** The manifest is the install database — a bad publish there breaks
//  downloads. News is append-mostly and republished often; links are set once
//  and then almost never touched. Keeping them apart means publishing a news
//  post can't clobber a link, and neither can damage the manifest.
//
//  Decoding here is **more forgiving than `Manifest.decode(from:)`**, on
//  purpose. The manifest refuses a payload whose `schemaVersion` it doesn't
//  understand, because misreading it installs the wrong thing. These are text
//  and URLs: the worst a misread entry can do is show nothing, so one bad row
//  must never cost the reader the whole document.
//

import Foundation

// MARK: - News

/// `Hashable` because the client pushes one onto a `NavigationStack` — the
/// full text of an entry is a page, not an inline expansion.
public struct NewsItem: Identifiable, Codable, Sendable, Hashable {

    public enum Category: String, Codable, Sendable, CaseIterable {
        case release
        case tip
        case announcement
    }

    public let id: String
    public let title: String
    public let body: String
    public let publishedAt: Date
    public let category: Category
    /// Optional "read more" link. Only `http`/`https` survives decoding.
    public let url: URL?
    /// Optional cover art, same trust rule as `url`.
    ///
    /// **There is deliberately only one image field.** It has to serve both a
    /// small row thumbnail and a full-width article hero on the client, so
    /// publish a *large* asset and let it downsample — a second "thumbnail"
    /// field is one more thing that can disagree with the first. Absent is a
    /// normal state: the client draws a title-derived card rather than
    /// reserving an empty rectangle.
    public let imageURL: URL?
    /// Shown only on builds at or above this version, so an entry about an
    /// unreleased feature can be written ahead of time.
    public let minAppVersion: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        publishedAt: Date = Date(),
        category: Category = .announcement,
        url: URL? = nil,
        imageURL: URL? = nil,
        minAppVersion: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.publishedAt = publishedAt
        self.category = category
        self.url = url
        self.imageURL = imageURL
        self.minAppVersion = minAppVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, publishedAt, category, url, imageURL, minAppVersion
    }

    /// Tolerant on everything that isn't load-bearing:
    ///
    /// - An **unknown `category`** becomes `.announcement` rather than
    ///   throwing, so publishing a new category from a newer Mullion-Admin
    ///   doesn't blank the feed on every client that shipped before it.
    /// - **`url` and `imageURL` are trusted only when `http`/`https`.** The
    ///   admin tool can leave a local `file://` path behind — the same trap
    ///   the manifest's `Game.iconURL` has — and the client hands one straight
    ///   to the system opener and the other to an image loader.
    /// - `id`, `title`, `body`, `publishedAt` are required: an entry missing
    ///   any of them has nothing to render, so it's dropped by `Failable`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)

        let rawCategory = try container.decodeIfPresent(String.self, forKey: .category)
        category = rawCategory.flatMap(Category.init(rawValue:)) ?? .announcement

        url = try container.decodeIfPresent(String.self, forKey: .url).flatMap(MullionURL.trusted(from:))
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL).flatMap(MullionURL.trusted(from:))
        minAppVersion = try container.decodeIfPresent(String.self, forKey: .minAppVersion)
    }
}

/// The `news.json` document.
///
/// `Equatable` so the admin tool can diff its working copy against the last
/// published state — that diff is the only thing telling an editor that
/// something is staged but not live.
public struct NewsDocument: Codable, Sendable, Equatable {
    public var items: [NewsItem]

    public init(items: [NewsItem] = []) {
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case items }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Element-wise tolerance: one malformed entry is skipped, its
        // siblings survive. Swift's synthesised array decoding is
        // all-or-nothing, which would lose the whole feed to one typo.
        items = try container.decode([Failable<NewsItem>].self, forKey: .items).compactMap(\.value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }

    public static func decode(from data: Data) throws -> NewsDocument {
        try Manifest.decoder().decode(NewsDocument.self, from: data)
    }

    public func encoded() throws -> Data {
        try Manifest.encoder().encode(self)
    }
}

// MARK: - App config (support & community links)

/// `app-config.json` — where the client's Support tab points.
///
/// Every field is optional, and that is the contract: **a `nil` link is not
/// rendered by the client at all.** No dead buttons, no "coming soon" rows.
/// Publishing a link switches its row on; clearing it switches the row off.
public struct AppConfig: Codable, Sendable, Equatable {

    /// A **public** repository used only for issues — no source. The standard
    /// arrangement for a closed-source app: reports stay public and
    /// searchable while the code stays private.
    ///
    /// This exists because pointing the client at the main repo's issues was
    /// tried and was wrong — that repository is private, so every user would
    /// have seen a 404.
    public var feedbackRepositoryURL: URL?
    public var discussionsURL: URL?
    public var telegramURL: URL?
    public var discordURL: URL?
    /// Falls back to a compiled-in address on the client when absent, since
    /// email is the one channel that needs nothing created.
    public var supportEmail: String?

    public init(
        feedbackRepositoryURL: URL? = nil,
        discussionsURL: URL? = nil,
        telegramURL: URL? = nil,
        discordURL: URL? = nil,
        supportEmail: String? = nil
    ) {
        self.feedbackRepositoryURL = feedbackRepositoryURL
        self.discussionsURL = discussionsURL
        self.telegramURL = telegramURL
        self.discordURL = discordURL
        self.supportEmail = supportEmail
    }

    private enum CodingKeys: String, CodingKey {
        case feedbackRepositoryURL, discussionsURL, telegramURL, discordURL, supportEmail
    }

    /// Every URL goes through the same `http`/`https` check as `NewsItem.url`,
    /// and an unusable one decodes to `nil` — which the client renders as
    /// "channel absent" rather than as a broken button.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func link(_ key: CodingKeys) throws -> URL? {
            try container.decodeIfPresent(String.self, forKey: key).flatMap(MullionURL.trusted(from:))
        }
        feedbackRepositoryURL = try link(.feedbackRepositoryURL)
        discussionsURL = try link(.discussionsURL)
        telegramURL = try link(.telegramURL)
        discordURL = try link(.discordURL)

        let email = try container.decodeIfPresent(String.self, forKey: .supportEmail)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        supportEmail = (email?.isEmpty == false) ? email : nil
    }

    public static func decode(from data: Data) throws -> AppConfig {
        try Manifest.decoder().decode(AppConfig.self, from: data)
    }

    public func encoded() throws -> Data {
        try Manifest.encoder().encode(self)
    }
}

// MARK: - App updates

/// One published build of Mullion, as `update.json` describes it.
///
/// **What the client does with this is deliberately small: it tells the user a
/// newer build exists and opens `downloadURL`.** Mullion installs nothing over
/// itself — there is no updater, no signed appcast and no relaunch — so this
/// document describes a release, it does not authorise one. Anything that
/// looked like an installer contract (a checksum, a signature, a delta) is
/// absent on purpose rather than published and ignored.
public struct AppRelease: Codable, Sendable, Equatable {

    /// `CFBundleShortVersionString` of the published build — "0.86". Compared
    /// against the running app's own by the client.
    public var version: String

    /// `CFBundleVersion`, when the release bumped it. Optional because a
    /// project that never touches its build counter would otherwise have to
    /// publish a number that means nothing; the client falls back to comparing
    /// `version` alone.
    public var build: String?

    /// Where the user is sent. **Required in practice**: a release with no
    /// download is a claim with no action behind it, so `UpdateDocument` drops
    /// one whose URL is missing or isn't `http`/`https`.
    public var downloadURL: URL

    /// A short line for the update row — "Fixes the Storage card's buttons."
    /// Long-form notes belong in News, which is already a reader for exactly
    /// that; this is the sentence that fits beside a Download button.
    public var notes: String?

    public var publishedAt: Date?

    /// The macOS version this build needs, as `ProcessInfo` states one —
    /// "27.0", "27.1". Present so a Mac that **cannot run** the new build is
    /// not told to go and fetch it: the client compares and stays quiet.
    /// Absent means "no newer requirement than the build already running".
    public var minimumSystemVersion: String?

    public init(
        version: String,
        build: String? = nil,
        downloadURL: URL,
        notes: String? = nil,
        publishedAt: Date? = nil,
        minimumSystemVersion: String? = nil
    ) {
        self.version = version
        self.build = build
        self.downloadURL = downloadURL
        self.notes = notes
        self.publishedAt = publishedAt
        self.minimumSystemVersion = minimumSystemVersion
    }

    private enum CodingKeys: String, CodingKey {
        case version, build, downloadURL, notes, publishedAt, minimumSystemVersion
    }

    /// `version` and a trusted `downloadURL` are the two fields without which
    /// there is nothing to say, so their absence throws and `UpdateDocument`
    /// turns that into "nothing published" rather than into an error the user
    /// sees. `downloadURL` gets the same `http`/`https` check every other link
    /// in this file gets — the admin tool can leave a `file://` path behind,
    /// and this one is handed straight to the system opener.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawVersion = try container.decode(String.self, forKey: .version)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawVersion.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container, debugDescription: "empty version"
            )
        }
        version = rawVersion

        let rawDownload = try container.decode(String.self, forKey: .downloadURL)
        guard let url = MullionURL.trusted(from: rawDownload) else {
            throw DecodingError.dataCorruptedError(
                forKey: .downloadURL, in: container,
                debugDescription: "downloadURL must be http or https"
            )
        }
        downloadURL = url

        func text(_ key: CodingKeys) throws -> String? {
            let raw = try container.decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }
        build = try text(.build)
        notes = try text(.notes)
        minimumSystemVersion = try text(.minimumSystemVersion)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
    }
}

/// The `update.json` document — the newest build Mullion-Admin has published.
///
/// **`latest` is optional and an empty document is the normal early state**,
/// exactly as `news.json`'s 404 is: nothing published yet means the client
/// says "you're up to date", never "update check failed". Unpublishing is
/// therefore possible without deleting the file — clear `latest` and every
/// client stops offering the build, which is the only recall mechanism a
/// system with no updater has.
///
/// A `latest` that fails to decode is treated the same way, through
/// `Failable`: a typo in a release entry must not turn into an error banner on
/// a screen the user opened to read their disk usage.
public struct UpdateDocument: Codable, Sendable, Equatable {
    public var latest: AppRelease?

    public init(latest: AppRelease? = nil) {
        self.latest = latest
    }

    private enum CodingKeys: String, CodingKey { case latest }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeIfPresent(Failable<AppRelease>.self, forKey: .latest)?.value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(latest, forKey: .latest)
    }

    public static func decode(from data: Data) throws -> UpdateDocument {
        try Manifest.decoder().decode(UpdateDocument.self, from: data)
    }

    public func encoded() throws -> Data {
        try Manifest.encoder().encode(self)
    }
}

// MARK: - Shared helpers

public enum MullionURL {
    /// A URL only counts if it's `http`/`https`.
    ///
    /// The manifest side of this system already learned this twice: a leading
    /// space in a saved URL once failed an entire decode, and `Game.iconURL`
    /// can still carry a leftover `file://` path from the admin UI. Trimming
    /// and scheme-checking in one place keeps both new documents out of that.
    public static func trusted(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}

/// Decodes `T`, or nothing, without failing its container.
struct Failable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
