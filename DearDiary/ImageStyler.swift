import UIKit
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins

/// Measurements taken from the aligned dear diary finals (2895 × 3860 px).
/// Everything is a fraction of the image WIDTH so it scales to any export size.
enum CaptionSpec {
    static let aspect: CGFloat = 4.0 / 3.0            // height / width (3:4 portrait)
    static let marginLeft: CGFloat = 222.0 / 2895     // text starts here
    static let ascenderHeight: CGFloat = 114.0 / 2895 // height of a lowercase "l"
    static let linePitch: CGFloat = 176.5 / 2895      // baseline to baseline
    static let topFirstBaseline: CGFloat = 597.0 / 2895
    static let bottomLastBaselineInset: CGFloat = 437.0 / 2895 // from the bottom edge
    static let maxLineWidth: CGFloat = 0.8633
    static let weight: UIFont.Weight = .medium

    /// SF Pro Medium, sized so a lowercase "l" is exactly `ascenderHeight` tall.
    static func font(forWidth width: CGFloat) -> UIFont {
        let probe = UIFont.systemFont(ofSize: 100, weight: weight)
        let ctFont = probe as CTFont
        var character: UniChar = 108 // "l"
        var glyph: CGGlyph = 0
        var rect = CGRect.zero
        if CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1) {
            CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, &rect, 1)
        }
        let lHeightAt100 = rect.maxY > 0 ? rect.maxY : 73.5
        return UIFont.systemFont(ofSize: width * ascenderHeight / lHeightAt100 * 100, weight: weight)
    }
}

/// Crops to 3:4, applies your look and grain, and prints the caption exactly like the originals.
enum ImageStyler {
    static let context = CIContext()

    static func render(source: UIImage,
                       caption: String,
                       position: TextPosition,
                       focus: CGPoint,
                       look: Look,
                       width: CGFloat,
                       seed: Int = 0,
                       adjust: PhotoAdjust = PhotoAdjust()) -> UIImage? {
        guard let cg = source.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let crop = cropRect(in: input.extent, focus: focus)
        var photoLook = look
        photoLook.exposure += adjust.exposure
        photoLook.shadows += adjust.shadows
        photoLook.saturation = max(photoLook.saturation + adjust.saturation * 0.5, 0)
        photoLook.warmth += adjust.warmth
        var styled = applyLook(input.cropped(to: crop), photoLook)
        if look.grain > 0.001 {
            styled = addGrain(to: styled, amount: look.grain, outputWidth: width, seed: seed)
        }
        guard let styledCG = context.createCGImage(styled, from: crop) else { return nil }

        let size = CGSize(width: width.rounded(), height: (width * CaptionSpec.aspect).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIImage(cgImage: styledCG).draw(in: CGRect(origin: .zero, size: size))
            drawCaption(caption, position: position, in: size, context: ctx.cgContext, shade: adjust.shade)
        }
    }

    /// 3:4 crop centred on the focus point (focus is measured from the top-left).
    static func cropRect(in extent: CGRect, focus: CGPoint) -> CGRect {
        let ratio: CGFloat = 1 / CaptionSpec.aspect // width / height = 0.75
        if extent.width / extent.height > ratio {
            let w = extent.height * ratio
            let cx = extent.minX + focus.x * extent.width
            let x = min(max(cx - w / 2, extent.minX), extent.maxX - w)
            return CGRect(x: x, y: extent.minY, width: w, height: extent.height).integral
        } else {
            let h = extent.width / ratio
            // Core Image's origin is bottom-left, so flip the focus.
            let cy = extent.maxY - focus.y * extent.height
            let y = min(max(cy - h / 2, extent.minY), extent.maxY - h)
            return CGRect(x: extent.minX, y: y, width: extent.width, height: h).integral
        }
    }

    static func applyLook(_ input: CIImage, _ look: Look) -> CIImage {
        var image = input

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = Float(look.exposure)
        image = exposure.outputImage ?? image

        // Deep shadows, gently rolled-off highlights.
        let s = CGFloat(look.shadows)
        let f = CGFloat(look.fade)
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0.0, y: 0.0 + f * 0.08)
        curve.point1 = CGPoint(x: 0.25, y: 0.25 - s * 0.07 + f * 0.04)
        curve.point2 = CGPoint(x: 0.5, y: 0.5 - s * 0.02)
        curve.point3 = CGPoint(x: 0.75, y: 0.76)
        curve.point4 = CGPoint(x: 1.0, y: 0.97)
        image = curve.outputImage ?? image

        let color = CIFilter.colorControls()
        color.inputImage = image
        color.contrast = Float(look.contrast)
        color.saturation = Float(look.saturation)
        color.brightness = 0
        image = color.outputImage ?? image

        let w = CGFloat(look.warmth) * 0.05
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: 1 + w, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1 - w, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        image = matrix.outputImage ?? image

        return image
    }

    /// Film-like monochrome grain, soft-light blended. Grain size is tied to the final
    /// image width so the preview and the export look the same.
    static func addGrain(to image: CIImage, amount: Double, outputWidth: CGFloat, seed: Int) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let extent = image.extent
        // How many source pixels one output pixel covers, times a grain size of ~1.6 output px.
        let grainScale = max(extent.width / max(outputWidth, 1), 0.1) * 1.6
        let offset = CGFloat(seed % 97) * 131
        let a = CGFloat(min(max(amount, 0), 1)) * 0.55

        let shaped = noise
            .transformed(by: CGAffineTransform(translationX: offset, y: offset * 0.7))
            .transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
            .applyingFilter("CIColorMatrix", parameters: [
                // Use the green channel as grey noise, pulled toward 50% grey by `a`.
                "inputRVector": CIVector(x: 0, y: a, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: a, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: a, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.5 - a / 2, y: 0.5 - a / 2, z: 0.5 - a / 2, w: 0)
            ])
            .cropped(to: extent)

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = shaped
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// SF Pro Medium, pure white, left-aligned, placed top / middle / bottom like the originals.
    static func drawCaption(_ text: String, position: TextPosition, in size: CGSize, context: CGContext, shade: Double = 0) {
        let width = size.width
        let height = size.height
        let font = CaptionSpec.font(forWidth: width)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let maxWidth = Double(width * CaptionSpec.maxLineWidth)

        // Wrap each paragraph; an empty paragraph is a blank line.
        var lines: [CTLine?] = []
        for paragraph in text.components(separatedBy: "\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                lines.append(nil)
                continue
            }
            let attributed = NSAttributedString(string: trimmed, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var start = 0
            while start < attributed.length {
                let count = max(CTTypesetterSuggestLineBreak(typesetter, start, maxWidth), 1)
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
                start += count
            }
        }
        guard !lines.isEmpty else { return }

        let pitch = width * CaptionSpec.linePitch
        let ascender = width * CaptionSpec.ascenderHeight
        let blockSpan = CGFloat(lines.count - 1) * pitch
        let firstBaseline: CGFloat
        switch position {
        case .top:
            firstBaseline = width * CaptionSpec.topFirstBaseline
        case .middle:
            let blockHeight = ascender + blockSpan
            firstBaseline = (height - blockHeight) / 2 + ascender
        case .bottom:
            firstBaseline = height - width * CaptionSpec.bottomLastBaselineInset - blockSpan
        }

        if shade > 0.001 {
            let blockTop = firstBaseline - ascender
            let blockBottom = firstBaseline + blockSpan + width * 0.012
            drawShade(amount: shade, position: position, blockTop: blockTop, blockBottom: blockBottom,
                      size: size, context: context)
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        let x = width * CaptionSpec.marginLeft
        for (i, line) in lines.enumerated() {
            guard let line else { continue }
            let baseline = firstBaseline + CGFloat(i) * pitch
            context.textPosition = CGPoint(x: x, y: height - baseline)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    /// A soft dark gradient behind the text so it reads on bright photos.
    static func drawShade(amount: Double, position: TextPosition, blockTop: CGFloat, blockBottom: CGFloat,
                          size: CGSize, context: CGContext) {
        let alpha = CGFloat(min(max(amount, 0), 1)) * 0.6
        let fade = size.width * 0.3
        let colors = [UIColor.black.withAlphaComponent(alpha).cgColor,
                      UIColor.black.withAlphaComponent(alpha * 0.55).cgColor,
                      UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        let locations: [CGFloat] = [0, 0.45, 1]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }

        context.saveGState()
        switch position {
        case .top:
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: 0, y: blockBottom + fade), options: [])
        case .bottom:
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height),
                                       end: CGPoint(x: 0, y: blockTop - fade), options: [])
        case .middle:
            let center = (blockTop + blockBottom) / 2
            let half = (blockBottom - blockTop) / 2 + fade
            context.clip(to: CGRect(x: 0, y: center - half, width: size.width, height: half))
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: center),
                                       end: CGPoint(x: 0, y: center - half), options: [])
            context.resetClip()
            context.clip(to: CGRect(x: 0, y: center, width: size.width, height: half))
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: center),
                                       end: CGPoint(x: 0, y: center + half), options: [])
        }
        context.restoreGState()
    }
}
