//
//  AvatarImageCache.swift
//  Sticks
//
//  Avatars are uploaded full-size (often 1-2 MB, several thousand
//  pixels across) but only ever drawn as small bubbles. AsyncImage has
//  no memory cache and decodes the full image every time a row is
//  rebuilt, which made every list in the app stutter and ballooned
//  memory. This loader downloads once, downsamples to a thumbnail off
//  the main thread, and keeps the thumbnails in memory. Concurrent
//  requests for the same URL share one download.
//

import ImageIO
import SwiftUI
import UIKit

nonisolated final class AvatarImageCache: @unchecked Sendable {
    static let shared = AvatarImageCache()

    /// Big enough for the largest avatar (profile header, ~80pt @3x).
    private static let maxPixelSize: CGFloat = 256

    private let memory = NSCache<NSURL, UIImage>()
    private let lock = NSLock()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        memory.countLimit = 400
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 0,
            diskCapacity: 80 * 1024 * 1024,
            diskPath: "sticks-avatars"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }

        let task: Task<UIImage?, Never> = lock.withLock {
            if let existing = inFlight[url] { return existing }
            let session = self.session
            let created = Task.detached(priority: .utility) { () -> UIImage? in
                guard let (data, _) = try? await session.data(from: url) else { return nil }
                return Self.downsample(data)
            }
            inFlight[url] = created
            return created
        }

        let image = await task.value
        lock.withLock { inFlight[url] = nil }
        if let image {
            memory.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    private static func downsample(_ data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Drop-in replacement for avatar AsyncImages: shows `placeholder`
/// until the cached thumbnail is ready (instantly when already cached).
struct RemoteAvatarImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        _image = State(initialValue: AvatarImageCache.shared.cached(url))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            if let hit = AvatarImageCache.shared.cached(url) {
                image = hit
                return
            }
            image = nil
            image = await AvatarImageCache.shared.image(for: url)
        }
    }
}
