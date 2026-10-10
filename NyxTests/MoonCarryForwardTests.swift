import Foundation
import Testing
import simd
@testable import Nyx

/// The Moon rules shared by the iPhone, the Vision Pro window and the Vision Pro globe.
@Suite("Moon shading shared with Vision Pro")
struct MoonCarryForwardTests {
    @Test("Large Moons draw on the atlas from 120 pt, on every surface")
    func atlasThreshold() {
        #expect(!MoonShading.usesAtlas(side: 119.9))
        #expect(MoonShading.usesAtlas(side: 120))
        // The Vision window's night panel Moon is 190 pt at the default size.
        #expect(MoonShading.usesAtlas(side: 190))
        #expect(MoonView.atlasSide == MoonShading.atlasSide)
        #expect(MoonView.reliefStrength == MoonShading.reliefStrength)
    }

    @Test("The globe drops its relief near full Moon, as the shader's fade does")
    func globeReliefNearFull() {
        func geometry(degrees: Double) -> MoonGeometry {
            MoonGeometry(phaseAngle: degrees*Double.pi/180, brightLimb: 1, north: 0, librationLongitude: 0, librationLatitude: 0)
        }
        #expect(!MoonShading.globeShowsRelief(geometry(degrees: 0)))
        #expect(!MoonShading.globeShowsRelief(geometry(degrees: 20)))
        #expect(MoonShading.globeShowsRelief(geometry(degrees: 27.5)))
        #expect(MoonShading.globeShowsRelief(geometry(degrees: 90)))
        #expect(MoonShading.globeShowsRelief(geometry(degrees: 175)))
    }

    @Test("The Sun's direction is the shader's: toward the viewer at full Moon, unit length")
    func sunDirection() {
        let full = MoonShading.sunDirection(MoonGeometry(phaseAngle: 0, brightLimb: 0.7, north: 0, librationLongitude: 0, librationLatitude: 0))
        #expect(abs(full.z-1) < 1e-12)
        let quarter = MoonShading.sunDirection(MoonGeometry(phaseAngle: Double.pi/2, brightLimb: Double.pi/2, north: 0, librationLongitude: 0, librationLatitude: 0))
        // Bright limb to the left (90° counterclockwise from up): the Sun is to the left.
        #expect(abs(quarter.x+1) < 1e-12 && abs(quarter.z) < 1e-12)
        #expect(abs(simd_length(quarter)-1) < 1e-12)
    }

    @Test("Every globe vertex samples the texel the Moon shader samples for that direction")
    func globeMatchesShader() {
        let columns = 192, rows = 96
        for i in stride(from: 0, through: columns, by: 7) {
            for j in stride(from: 1, to: rows, by: 5) {
                let vertex = MoonGlobeGrid.vertex(column: i, row: j, columns: columns, rows: rows)
                let shader = MoonGlobeGrid.shaderUV(SIMD3<Double>(vertex.normal))
                // u wraps at the seam (the last column is u = 1, the shader's 0); v runs up from the bottom.
                let du = abs(Double(vertex.uv.x)-shader.x)
                #expect(min(du, abs(du-1)) < 1e-4)
                #expect(abs(Double(vertex.uv.y)-(1-shader.y)) < 1e-4)
            }
        }
        // The mean near side faces +z, lunar north is up.
        let centre = MoonGlobeGrid.vertex(column: 96, row: 48, columns: columns, rows: rows)
        #expect(simd_distance(centre.normal, [0, 0, 1]) < 1e-5)
        #expect(simd_distance(MoonGlobeGrid.vertex(column: 0, row: rows, columns: columns, rows: rows).normal, [0, 1, 0]) < 1e-5)
    }

    @Test("Tangents point east and bitangents north, a right-handed frame around the outward normal")
    func globeTangentFrame() {
        let columns = 192, rows = 96
        for (i, j) in [(96, 48), (10, 20), (150, 70), (48, 90), (191, 5)] {
            let v = MoonGlobeGrid.vertex(column: i, row: j, columns: columns, rows: rows)
            #expect(abs(simd_dot(v.tangent, v.normal)) < 1e-5)
            #expect(abs(simd_dot(v.bitangent, v.normal)) < 1e-5)
            #expect(simd_distance(simd_cross(v.tangent, v.bitangent), v.normal) < 1e-4)
            // Along the grid: the next column lies east (+u), the next row north (+v).
            let east = MoonGlobeGrid.vertex(column: i+1, row: j, columns: columns, rows: rows)
            let north = MoonGlobeGrid.vertex(column: i, row: j+1, columns: columns, rows: rows)
            #expect(simd_dot(east.normal-v.normal, v.tangent) > 0)
            #expect(simd_dot(north.normal-v.normal, v.bitangent) > 0)
            #expect(east.uv.x > v.uv.x && north.uv.y > v.uv.y)
        }
    }
}
