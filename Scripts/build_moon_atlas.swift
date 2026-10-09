// Builds Nyx/Resources/MoonRelief.xcassets/MoonAtlas.imageset/MoonAtlas.jpg: the large Moon's
// colour map and its local relief, packed into one picture because the Moon shader takes a single
// image argument.
//
// Sources (NASA SVS CGI Moon Kit, https://svs.gsfc.nasa.gov/4720, public domain):
//   lroc_color_poles_4k.tif  4096×2048 RGB, LRO Camera colour mosaic (the family of MoonMap.jpg)
//     https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/lroc_color_poles_4k.tif
//   ldem_16_uint.tif         5760×2880 16-bit elevation in half-metres, LRO LOLA
//     https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/ldem_16_uint.tif
// Both are equirectangular with longitude 0 at the centre and north up.
//
// Layout (4096×3072): rows 0–2047 hold the colour map; rows 2048–3071, columns 0–2047 hold the
// height map at 2048×1024 (one texel about 5.3 km at the equator); the rest is black. The height is
// local relief: elevation minus its own blur (two box passes of radius 16 texels, about 85 km),
// so the 8 bits carry crater-scale detail instead of the Moon's 20 km total range. Grey 128 is the
// local mean; the step in metres per grey level is printed and is the constant in `Moon.metal`.
//
// Usage: swift -O Scripts/build_moon_atlas.swift <source folder> <output.jpg>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: build_moon_atlas.swift <source folder> <output.jpg>"); exit(2) }
let folder = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])

func load(_ name: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("cannot read \(name)"); exit(1) }
    return image
}

// Elevation, read at full size as native 16-bit grey.
let dem = load("ldem_16_uint.tif")
let sw = dem.width, sh = dem.height
var raw = [UInt16](repeating: 0, count: sw * sh)
raw.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(data: buffer.baseAddress, width: sw, height: sh, bitsPerComponent: 16, bytesPerRow: sw * 2,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
    else { print("no 16-bit context"); exit(1) }
    context.interpolationQuality = .none
    context.draw(dem, in: CGRect(x: 0, y: 0, width: sw, height: sh))
}

// Area-averaged to 2048×1024, in metres.
let hw = 2048, hh = 1024
func resample(_ input: [Double], width: Int, height: Int, to outWidth: Int, horizontal: Bool) -> [Double] {
    let inLength = horizontal ? width : height, lines = horizontal ? height : width
    let factor = Double(inLength) / Double(outWidth)
    var out = [Double](repeating: 0, count: outWidth * lines)
    for line in 0..<lines {
        for o in 0..<outWidth {
            let a = Double(o) * factor, b = a + factor
            var sum = 0.0, weight = 0.0, i = Int(a)
            while Double(i) < b && i < inLength {
                let w = min(b, Double(i + 1)) - max(a, Double(i))
                let value = horizontal ? input[line * width + i] : input[i * width + line]
                sum += value * w; weight += w; i += 1
            }
            if horizontal { out[line * outWidth + o] = sum / weight } else { out[o * width + line] = sum / weight }
        }
    }
    return out
}
let metres = raw.map { Double($0) * 0.5 }
let across = resample(metres, width: sw, height: sh, to: hw, horizontal: true)          // hw × sh
let height = resample(across, width: hw, height: sh, to: hh, horizontal: false)         // hw × hh

// Local relief: subtract a soft blur (wrapping in longitude, clamped at the poles).
func box(_ input: [Double], radius r: Int) -> [Double] {
    var tmp = [Double](repeating: 0, count: input.count), out = tmp
    let n = Double(2 * r + 1)
    for y in 0..<hh { for x in 0..<hw {
        var s = 0.0
        for d in -r...r { s += input[y * hw + ((x + d) % hw + hw) % hw] }
        tmp[y * hw + x] = s / n
    } }
    for y in 0..<hh { for x in 0..<hw {
        var s = 0.0
        for d in -r...r { s += tmp[min(hh - 1, max(0, y + d)) * hw + x] }
        out[y * hw + x] = s / n
    } }
    return out
}
let blurred = box(box(height, radius: 16), radius: 16)
let relief = zip(height, blurred).map { $0 - $1 }
let sorted = relief.map(abs).sorted()
let p999 = sorted[Int(Double(sorted.count) * 0.999)]
let step = p999 / 120   // metres per grey level; 99.9% of texels fit without clipping
print(String(format: "relief: 99.9th percentile %.0f m, step %.2f m per level", p999, step))
var grey = [UInt8](repeating: 0, count: hw * hh)
for i in 0..<relief.count { grey[i] = UInt8(max(0, min(255, (128 + relief[i] / step).rounded()))) }

// Pack: colour on top, relief bottom-left.
let colour = load("lroc_color_poles_4k.tif")
let aw = 4096, ah = 3072
guard colour.width == aw, colour.height == 2048,
      let atlas = CGContext(data: nil, width: aw, height: ah, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { print("unexpected colour map size"); exit(1) }
atlas.setFillColor(CGColor(gray: 0, alpha: 1)); atlas.fill(CGRect(x: 0, y: 0, width: aw, height: ah))
atlas.interpolationQuality = .none
atlas.draw(colour, in: CGRect(x: 0, y: ah - 2048, width: aw, height: 2048))   // CG's origin is bottom-left
// The relief is written byte for byte (no colour conversion), as grey in all three channels.
guard let data = atlas.data?.assumingMemoryBound(to: UInt8.self) else { exit(1) }
let rowBytes = atlas.bytesPerRow
for y in 0..<hh { for x in 0..<hw {
    let g = grey[y * hw + x], o = (2048 + y) * rowBytes + x * 4   // memory rows run top to bottom
    data[o] = g; data[o + 1] = g; data[o + 2] = g
} }
guard let final = atlas.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
else { print("cannot pack"); exit(1) }
CGImageDestinationAddImage(destination, final, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { print("cannot write"); exit(1) }
print("wrote \(output.path)")
