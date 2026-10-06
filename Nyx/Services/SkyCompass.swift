import Foundation
import simd

/// "Where to look": the sky's altitude and azimuth turned to wherever the phone is pointing.
/// The phone is treated as a window: what lies straight out of its back sits at the centre of the
/// screen. Pure geometry, so it is tested without a device. Vectors are east, north, up.
nonisolated enum SkyCompass {
    /// The window's horizontal field of view, about what a phone camera sees.
    static let fieldOfView=60.0

    /// A unit vector toward altitude/azimuth (degrees; azimuth from north through east).
    static func direction(altitude: Double, azimuth: Double) -> SIMD3<Double> {
        let alt=altitude*Double.pi/180, az=azimuth*Double.pi/180
        return SIMD3(cos(alt)*sin(az), cos(alt)*cos(az), sin(alt))
    }
    static func altitudeAzimuth(_ v: SIMD3<Double>) -> (altitude: Double, azimuth: Double) {
        let n=simd_normalize(v)
        let az=atan2(n.x, n.y)*180/Double.pi
        return (asin(max(-1, min(1, n.z)))*180/Double.pi, az<0 ? az+360 : az)
    }

    /// Where the phone points: the view direction out of its back, and the screen's up and right.
    struct Pose: Sendable, Equatable {
        let look: SIMD3<Double>
        let up: SIMD3<Double>
        let right: SIMD3<Double>
        init(axes look: SIMD3<Double>, _ up: SIMD3<Double>, _ right: SIMD3<Double>) { self.look=look; self.up=up; self.right=right }
        var altitude: Double { altitudeAzimuth(look).altitude }
        var azimuth: Double { altitudeAzimuth(look).azimuth }
        /// Held upright toward `azimuth`, tipped back by `altitude`, turned by `roll` (degrees,
        /// clockwise as the person sees the screen).
        init(azimuth: Double, altitude: Double, roll: Double=0) {
            let look=direction(altitude: altitude, azimuth: azimuth)
            // Toward the zenith, square to the view; straight up or down, the top of the phone faces the azimuth.
            let zenith=SIMD3<Double>(0, 0, 1)
            var up=zenith-simd_dot(zenith, look)*look
            if simd_length(up)<1e-6 { up=direction(altitude: 0, azimuth: azimuth)*(altitude>0 ? -1 : 1) }
            up=simd_normalize(up)
            let right=simd_cross(look, up)
            let r=roll*Double.pi/180
            self.look=look
            self.up=simd_normalize(up*cos(r)+right*sin(r))
            self.right=simd_normalize(right*cos(r)-up*sin(r))
        }
        /// From Core Motion: the attitude quaternion and gravity, both in the device frame (x right,
        /// y toward the top, z out of the screen), in a reference frame with x north, y west, z up.
        /// The quaternion is applied whichever way makes gravity point down, so a convention slip
        /// can never turn the sky upside down.
        init(quaternion q: simd_quatd, gravity: SIMD3<Double>) {
            var rotation=q
            if simd_length(gravity)>0.1, rotation.act(simd_normalize(gravity)).z > -0.5, q.inverse.act(simd_normalize(gravity)).z < -0.5 { rotation=q.inverse }
            func world(_ v: SIMD3<Double>) -> SIMD3<Double> { let r=rotation.act(v); return SIMD3(-r.y, r.x, r.z) }
            look=simd_normalize(world(SIMD3(0, 0, -1)))
            up=simd_normalize(world(SIMD3(0, 1, 0)))
            right=simd_normalize(world(SIMD3(1, 0, 0)))
        }
    }

    /// A sky position on a screen of `size` (points, origin top-left). `point` is nil when the
    /// target is behind the viewer or (when `clipped`) outside the screen; `edgeAngle` is then the direction to turn
    /// toward it, in screen terms (0 = right, π/2 = up).
    struct Placement: Sendable, Equatable {
        let point: SIMD2<Double>?
        let edgeAngle: Double
        /// Degrees between the view direction and the target.
        let separation: Double
    }
    static func place(altitude: Double, azimuth: Double, pose: Pose, width: Double, height: Double, fieldOfView: Double=fieldOfView, clipped: Bool=true) -> Placement {
        let t=direction(altitude: altitude, azimuth: azimuth)
        let z=simd_dot(t, pose.look), x=simd_dot(t, pose.right), y=simd_dot(t, pose.up)
        let separation=acos(max(-1, min(1, z)))*180/Double.pi
        let angle=atan2(y, x)
        guard z>0.05 else { return Placement(point: nil, edgeAngle: angle, separation: separation) }
        let focal=(width/2)/tan(fieldOfView*Double.pi/360)
        let p=SIMD2(width/2+focal*x/z, height/2-focal*y/z)
        let onScreen = !clipped || (p.x>=0 && p.x<=width && p.y>=0 && p.y<=height)
        return Placement(point: onScreen ? p : nil, edgeAngle: angle, separation: separation)
    }
    /// Spoken: "32° up, east-southeast", or "below the horizon".
    static func spoken(altitude: Double, azimuth: Double) -> String {
        altitude < -0.5 ? String(localized: "below the horizon") : String(localized: "\(Int(max(0, altitude).rounded()))° up, \(Compass.fine(azimuth))")
    }
}

extension Compass {
    /// Sixteen points: "east-southeast".
    nonisolated static func fine(_ azimuth: Double) -> String {
        let index=Int(((azimuth.truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)/22.5).rounded())%16
        return [String(localized: "north"), String(localized: "north-northeast"), String(localized: "northeast"), String(localized: "east-northeast"),
                String(localized: "east"), String(localized: "east-southeast"), String(localized: "southeast"), String(localized: "south-southeast"),
                String(localized: "south"), String(localized: "south-southwest"), String(localized: "southwest"), String(localized: "west-southwest"),
                String(localized: "west"), String(localized: "west-northwest"), String(localized: "northwest"), String(localized: "north-northwest")][index]
    }
}
