//
//  EsriImageryTileOverlay.swift
//  Sticks
//
//  Slice 66: Esri "World Imagery" raster tiles for the on-course map —
//  sharper, greener source photos than Apple's satellite layer on many
//  resort/coastal courses. Each tile gets a modest saturation/contrast
//  lift as it loads (mirrors the web's Mapbox raster tune); on any
//  failure the raw bytes ship as-is, and because canReplaceMapContent
//  is false, Apple imagery shows through any gap entirely.
//

import CoreImage
import MapKit
import UIKit

nonisolated final class EsriImageryTileOverlay: MKTileOverlay {
    /// CIContext is documented thread-safe — shared across the tile
    /// loader's background completion threads.
    private nonisolated(unsafe) static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static let base =
        "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile"

    init() {
        // Esri World Imagery: path order is {z}/{y}/{x}. blankTile=false
        // makes a missing tile a 404 instead of Esri's grey
        // "Map data not yet available" placeholder, so we can fall back.
        super.init(urlTemplate: Self.base + "/{z}/{y}/{x}?blankTile=false")
        canReplaceMapContent = false   // let Apple imagery show through any gap/failure
        maximumZ = 20                  // Esri thins out past ~20 in some areas
        tileSize = CGSize(width: 256, height: 256)
    }

    /// Fetch the tile, then a modest saturation/contrast lift so turf
    /// reads greener + crisper. When Esri has no imagery at this zoom
    /// (short par 3s zoom past it — Pebble Beach 7), crop and upscale
    /// the nearest ancestor tile that exists, up to 4 levels up.
    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        Self.fetch(z: path.z, x: path.x, y: path.y, levelsUp: 0) { data, error in
            guard let data else { result(nil, error); return }
            result(Self.tuned(data) ?? data, nil)
        }
    }

    private static func fetch(z: Int, x: Int, y: Int, levelsUp: Int,
                              completion: @escaping (Data?, Error?) -> Void) {
        let az = z - levelsUp
        let ax = x >> levelsUp
        let ay = y >> levelsUp
        guard let url = URL(string: "\(base)/\(az)/\(ay)/\(ax)?blankTile=false") else {
            completion(nil, URLError(.badURL)); return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, error == nil, status == 200 {
                if levelsUp == 0 { completion(data, nil); return }
                completion(crop(data, levelsUp: levelsUp, x: x, y: y) ?? data, nil)
                return
            }
            if status == 404, levelsUp < 4, az > 1 {
                fetch(z: z, x: x, y: y, levelsUp: levelsUp + 1, completion: completion)
                return
            }
            completion(nil, error ?? URLError(.fileDoesNotExist))
        }.resume()
    }

    /// Cut the requested tile's square out of an ancestor tile and scale
    /// it back up to 256 px.
    private static func crop(_ data: Data, levelsUp: Int, x: Int, y: Int) -> Data? {
        guard let src = CIImage(data: data) else { return nil }
        let divisions = 1 << levelsUp
        let side = src.extent.width / CGFloat(divisions)
        let col = CGFloat(x % divisions)
        let row = CGFloat(y % divisions)
        // Core Image's origin is bottom-left; tile rows count from the top.
        let rect = CGRect(x: col * side,
                          y: src.extent.height - (row + 1) * side,
                          width: side, height: side)
        let scale = 256 / side
        let out = src.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ciContext.createCGImage(out, from: CGRect(x: 0, y: 0, width: 256, height: 256))
        else { return nil }
        return UIImage(cgImage: cg).pngData()
    }

    private static func tuned(_ data: Data) -> Data? {
        guard let src = CIImage(data: data) else { return nil }
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(src, forKey: kCIInputImageKey)
        filter.setValue(1.18, forKey: kCIInputSaturationKey)  // greener
        filter.setValue(1.06, forKey: kCIInputContrastKey)    // crisper
        filter.setValue(0.02, forKey: kCIInputBrightnessKey)  // a touch brighter
        guard let out = filter.outputImage,
              let cg = ciContext.createCGImage(out, from: src.extent)
        else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
}
