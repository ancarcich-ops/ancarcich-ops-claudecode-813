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

    init() {
        // Esri World Imagery: path order is {z}/{y}/{x}.
        super.init(urlTemplate:
            "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}")
        canReplaceMapContent = false   // let Apple imagery show through any gap/failure
        maximumZ = 20                  // Esri thins out past ~20 in some areas
        tileSize = CGSize(width: 256, height: 256)
    }

    /// Fetch the tile, then a modest saturation/contrast lift so turf
    /// reads greener + crisper. On any failure we return the raw bytes
    /// rather than nothing.
    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        let url = self.url(forTilePath: path)
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil else { result(data, error); return }
            result(Self.tuned(data) ?? data, nil)
        }.resume()
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
