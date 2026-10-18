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
