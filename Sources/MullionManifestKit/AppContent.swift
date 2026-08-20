//
//  AppContent.swift
//  MullionManifestKit
//
//  Two documents published alongside `manifest.json` in the same
//  `mullion-runtime` repo, written by Mullion-Admin and read by Mullion:
//
//  - `news.json`      — the client's News tab
//  - `app-config.json` — support and community links
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
