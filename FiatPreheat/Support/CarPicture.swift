import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// A picture for cars the app ships none of: the brand's own picture of the car, cut out of its
/// background on the phone (Vision's subject lifting), placed where the 500e pictures sit on the
/// same 1200×640 canvas, and kept on disk per car.
enum CarPicture {
    /// Where the car sits on the canvas, matching the bundled 500e pictures.
    static let canvas = CGSize(width: 1200, height: 640)
    static let carBox = CGRect(x: 298, y: 176, width: 602, height: 314)

    /// Leaves the picture where the widgets can read it.
    static func shareWithWidgets(_ image: UIImage) {
        guard let url = CarSnapshot.sharedPictureURL, shared !== image else { return }
        try? image.pngData()?.write(to: url)
        shared = image
    }
    nonisolated(unsafe) private static var shared: UIImage?

    static func cached(vin: String) -> UIImage? {
        UIImage(contentsOfFile: file(vin).path)
    }

    static func make(vin: String, from url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let cut = lift(source) ?? source
        guard let placed = place(cut) else { return nil }
        try? FileManager.default.createDirectory(at: file(vin).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? placed.pngData()?.write(to: file(vin))
        return placed
    }

    private static func file(_ vin: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "Cars/\(vin).png")
    }

    /// The car alone, with the background transparent. Nil when Vision finds no subject.
    private static func lift(_ image: CIImage) -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil, let result = request.results?.first,
              let mask = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) else { return nil }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage(color: .clear).cropped(to: image.extent)
        blend.maskImage = CIImage(cvPixelBuffer: mask)
        return blend.outputImage
    }

    /// Crops to the car and fits it into `carBox`, standing on its bottom edge.
    private static func place(_ image: CIImage) -> UIImage? {
        let context = CIContext()
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        let bounds = opaqueBounds(cg) ?? CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        guard let car = cg.cropping(to: bounds) else { return nil }
        let scale = min(carBox.width / bounds.width, carBox.height / bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let origin = CGPoint(x: carBox.midX - size.width / 2, y: carBox.maxY - size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            UIImage(cgImage: car).draw(in: CGRect(origin: origin, size: size))
        }
    }

    /// The box around pixels that aren't (nearly) transparent.
    private static func opaqueBounds(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Row 0 of the buffer is the top of the picture, as cropping counts.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

extension CarPicture {
    /// Where a placed picture meets the ground: the lower hull of its silhouette (the line through
    /// its lowest points) and the tyres, found as bumps in the lower edge that stand at least 10 pt
    /// below the edge on either side.
    static func ground(of image: UIImage) -> GroundShape? {
        guard let cg = image.cgImage else { return nil }
        let w = Int(canvas.width), h = Int(canvas.height)
        var alpha = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &alpha, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Lowest solid pixel per column (row 0 of the buffer is the top of the picture).
        var bottom = [Int](repeating: -1, count: w)
        for x in 0..<w {
            for y in stride(from: h - 1, through: 0, by: -1) where alpha[y * w + x] > 128 { bottom[x] = y; break }
        }
        let xs = (0..<w).filter { bottom[$0] >= 0 }
        guard let minX = xs.first, let maxX = xs.last else { return nil }

        // Lower hull (y grows downward), sampled every 6 columns.
        var hull: [CGPoint] = []
        for x in stride(from: minX, through: maxX, by: 6) where bottom[x] >= 0 {
            let p = CGPoint(x: x, y: bottom[x])
            while hull.count >= 2 {
                let a = hull[hull.count - 2], b = hull[hull.count - 1]
                if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0 { hull.removeLast() } else { break }
            }
            hull.append(p)
        }

        var tyres: [CGRect] = []
        var used = Set<Int>()
        for x in xs.sorted(by: { bottom[$0] > bottom[$1] }) where !used.contains(x) {
            let lo = max(minX, x - 70), hi = min(maxX, x + 70)
            let window = (lo...hi).map { bottom[$0] }
            defer { used.formUnion(lo...hi) }
            guard bottom[x] >= window.max() ?? 0 else { continue }
            let sides = min(bottom[max(minX, x - 90)], bottom[min(maxX, x + 90)])
            guard bottom[x] - sides >= 10 else { continue }
            let cols = (lo...hi).filter { bottom[$0] >= bottom[x] - 4 }
            let cx = CGFloat(cols.reduce(0, +)) / CGFloat(cols.count)
            let width = CGFloat((cols.max() ?? x) - (cols.min() ?? x)) * 1.3
            tyres.append(CGRect(x: cx - width / 2, y: CGFloat(bottom[x]) - 7, width: width, height: 13))
        }
        return GroundShape(hull: hull, tyres: tyres)
    }
}
