// Builds the two textures of the Vision Pro Moon volume's globe ("The Moon on your table"),
// NyxVision/Resources/MoonGlobe/:
//   MoonGlobeColour.ktx  4096×2048, the LRO Camera colour mosaic as it is (the colour band of MoonAtlas),
//                        ASTC 6×6 sRGB with mipmaps (about 5 MB on disk and in GPU memory)
//   MoonGlobeNormal.ktx  2048×1024, a tangent-space normal map baked from LOLA elevation,
//                        ASTC 4×4 with mipmaps (about 2.8 MB)
// As plain RGBA with mipmaps the pair would take some 53 MB of texture memory; visionOS cannot
// compress at run time (`TextureResource.Compression.astc` is unavailable there), so the script
// compresses them with Xcode's TextureConverter (xcrun TextureConverter), from a lossless
// intermediate (PNG for both) kept in a temporary folder.
// Both are equirectangular, longitude 0 at the centre, north up: the layout `Moon.metal` samples and
// `MoonGlobeGrid` maps onto the globe.
//
// Sources (NASA SVS CGI Moon Kit, https://svs.gsfc.nasa.gov/4720, public domain), the same two files
// as Scripts/build_moon_atlas.swift:
//   lroc_color_poles_4k.tif  4096×2048 RGB, LRO Camera colour mosaic
//     https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/lroc_color_poles_4k.tif
//   ldem_16_uint.tif         5760×2880 16-bit elevation in half-metres, LRO LOLA
//     https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/ldem_16_uint.tif
//
// The normal map: elevation area-averaged to 2048×1024 (one texel about 5.3 km at the equator), its
// slopes taken by central differences over two texels on a sphere of 1,737.4 km (east-west slopes
// divided by the cosine of latitude, which grows the texel's real width back), exaggerated by the
// iPhone Moon's relief strength (2.5, `MoonShading.reliefStrength`) so crater rims read on a 28 cm
// globe, and written as a unit normal in the surface's own frame: red along east (+u), green along
// north (+v in RealityKit's texture coordinates, which run up from the image's bottom), blue out of
// the surface. 128,128,255 is flat.
//
// The normal map is written as RGB, not TextureConverter's normal-map mode (which keeps only X and
// Y), because RealityKit's material reads all three channels.
//
// Usage: swift -O Scripts/build_moon_globe.swift <source folder> <output folder>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: build_moon_globe.swift <source folder> <output folder>"); exit(2) }
let folder = URL(fileURLWithPath: args[1]), finalFolder = URL(fileURLWithPath: args[2])
let outFolder = FileManager.default.temporaryDirectory.appendingPathComponent("moon-globe-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)
let strength = 2.5
let moonRadius = 1_737_400.0

func load(_ name: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("cannot read \(name)"); exit(1) }
    return image
}
func write(_ image: CGImage, _ name: String, _ type: UTType, _ options: [CFString: Any] = [:]) {
    let url = outFolder.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { print("cannot write \(name)"); exit(1) }
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { print("cannot write \(name)"); exit(1) }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("wrote \(url.path) (\(image.width)×\(image.height), \(bytes / 1024) KB)")
}

// Colour: the mosaic itself, in sRGB.
let colour = load("lroc_color_poles_4k.tif")
guard colour.width == 4096, colour.height == 2048,
      let colourContext = CGContext(data: nil, width: 4096, height: 2048, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { print("unexpected colour map size"); exit(1) }
colourContext.interpolationQuality = .none
colourContext.draw(colour, in: CGRect(x: 0, y: 0, width: 4096, height: 2048))
guard let colourImage = colourContext.makeImage() else { exit(1) }
write(colourImage, "MoonGlobeColour.png", .png)

// Elevation, read at full size as native 16-bit grey, in metres.
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

// Area-averaged to 2048×1024 (the atlas script's resampler).
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
let across = resample(metres, width: sw, height: sh, to: hw, horizontal: true)
let height = resample(across, width: hw, height: sh, to: hh, horizontal: false)

// Slopes and normals. Rows run north to south; longitude wraps, latitude stops at the poles.
let texel = 2 * Double.pi / Double(hw)
var pixels = [UInt8](repeating: 0, count: hw * hh * 4)
var steepest = 0.0
for y in 0..<hh {
    let latitude = (0.5 - (Double(y) + 0.5) / Double(hh)) * Double.pi
    let width = max(cos(latitude), 0.15)
    let up = max(0, y - 1), down = min(hh - 1, y + 1)
    for x in 0..<hw {
        let east = height[y * hw + (x + 1) % hw] - height[y * hw + (x - 1 + hw) % hw]
        let north = height[up * hw + x] - height[down * hw + x]
        let gEast = east / (moonRadius * Double(2) * texel * width) * strength
        let gNorth = north / (moonRadius * Double(down - up) * texel) * strength
        steepest = max(steepest, atan(hypot(gEast, gNorth)) * 180 / Double.pi)
        let length = sqrt(gEast * gEast + gNorth * gNorth + 1)
        let n = (-gEast / length, -gNorth / length, 1 / length)
        let o = (y * hw + x) * 4
        pixels[o] = UInt8(((n.0 * 0.5 + 0.5) * 255).rounded())
        pixels[o + 1] = UInt8(((n.1 * 0.5 + 0.5) * 255).rounded())
        pixels[o + 2] = UInt8(((n.2 * 0.5 + 0.5) * 255).rounded())
        pixels[o + 3] = 255
    }
}
print(String(format: "normals: steepest exaggerated slope %.0f°", steepest))
// Written byte for byte, untagged, so no colour management touches the vectors.
guard let provider = CGDataProvider(data: Data(pixels) as CFData),
      let normalImage = CGImage(width: hw, height: hh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: hw * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
else { print("cannot build normals"); exit(1) }
write(normalImage, "MoonGlobeNormal.png", .png)

// GPU compression, with a full mip chain that wraps across the seam.
func compress(_ input: String, _ output: String, _ options: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["TextureConverter"] + options + ["--compression_quality=Highest", "--wrap_mode=Repeat",
        "--output=\(finalFolder.appendingPathComponent(output).path)", outFolder.appendingPathComponent(input).path]
    process.standardOutput = FileHandle.nullDevice
    do { try process.run() } catch { print("cannot run TextureConverter: \(error)"); exit(1) }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { print("TextureConverter failed on \(input)"); exit(1) }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: finalFolder.appendingPathComponent(output).path)[.size] as? Int) ?? 0
    print("wrote \(finalFolder.appendingPathComponent(output).path) (\(bytes / 1024) KB)")
}
compress("MoonGlobeColour.png", "MoonGlobeColour.ktx", ["--compression_format=ASTC6x6", "--srgb_format", "--gamma_in=sRGB", "--gamma_out=sRGB"])
compress("MoonGlobeNormal.png", "MoonGlobeNormal.ktx", ["--compression_format=ASTC4x4"])
try? FileManager.default.removeItem(at: outFolder)
