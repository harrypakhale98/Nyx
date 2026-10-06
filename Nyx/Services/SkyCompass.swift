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
        /// The same pointing, seen through a screen turned `quarterTurns` from the device's own
        /// portrait (an iPad in landscape): the view direction is unchanged; the screen's up and
        /// right turn. 1: the device's top at the screen's left (interface landscape right);
        /// 2: upside down; 3: the top at the screen's right (landscape left).
        func turned(_ quarterTurns: Int) -> Pose {
            switch (quarterTurns%4+4)%4 {
            case 1: Pose(axes: look, right, -up)
            case 2: Pose(axes: look, -up, -right)
            case 3: Pose(axes: look, -right, up)
            default: self
            }
        }
    }

    /// The horizontal field of view for a window `width` by `height`: the shorter side always spans
    /// `fieldOfView`, so an iPad in landscape shows more sky beside the target, not a zoomed one.
    static func horizontalFieldOfView(width: Double, height: Double) -> Double {
        guard width>height, height>0 else { return fieldOfView }
        return 2*atan(tan(fieldOfView*Double.pi/360)*width/height)*180/Double.pi
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
    /// A point on the Milky Way's centre line (galactic latitude 0, J2000, radians), with the band's
    /// brightness there (0.35…1, RealSky's model: brightest toward the core in Sagittarius, faintest
    /// toward the anticentre) and its half-width in degrees (about 6° on the faint side, 13° at the core).
    struct BandPoint: Sendable, Equatable { let ra: Double; let dec: Double; let brightness: Double; let halfWidth: Double }
    /// The galactic plane every `step` degrees of galactic longitude, from the north galactic pole
    /// (RA 192.859°, Dec +27.128°) and the ascending node's longitude (122.932°).
    static func galacticPlane(step: Double=3) -> [BandPoint] {
        let rad=Double.pi/180, poleRA=192.85948*rad, poleDec=27.12825*rad, nodeL=122.93192*rad
        return stride(from: 0.0, to: 360, by: max(0.5, step)).map { degrees in
            let l=degrees*rad
            let dec=asin(cos(poleDec)*cos(nodeL-l))
            var ra=poleRA+atan2(sin(nodeL-l), -sin(poleDec)*cos(nodeL-l))
            ra=ra.truncatingRemainder(dividingBy: 2*Double.pi); if ra<0 { ra+=2*Double.pi }
            let toCore=(1+cos(l))/2
            return BandPoint(ra: ra, dec: dec, brightness: 0.35+0.65*toCore*toCore, halfWidth: 6+7*pow(toCore, 4))
        }
    }
    /// How much of the Milky Way a dark-adapted eye can see, 0…1: none until the Sun is 12° down and
    /// all of it from 18° (astronomical twilight's end); a Moon above the horizon washes it out by the
    /// square root of its lit fraction (a quarter Moon already takes most of it); sky glow leaves all of
    /// it under Bortle 1–3 and none from Bortle 7.
    static func milkyWayVisibility(sunAltitude: Double, moonAltitude: Double, moonIllumination: Double, bortle: Int) -> Double {
        let night=min(1, max(0, (-12-sunAltitude)/6))
        let moonUp=min(1, max(0, (moonAltitude+1)/6))
        let moon=1-0.9*moonUp*max(0, min(1, moonIllumination)).squareRoot()
        let glow=min(1, max(0, Double(7-bortle)/4))
        return night*moon*glow
    }
    /// The sky's side of the horizon on screen, as a polygon to clip to: the horizon is a great circle,
    /// so through this window it is a straight line; the polygon is that line, closed far out on the
    /// zenith's side. Nil when the horizon is out of view (then the screen is all sky or all ground).
    static func skySide(pose: Pose, width: Double, height: Double, fieldOfView: Double=fieldOfView) -> [SIMD2<Double>]? {
        // Swept from behind the viewer, so the part in front comes as one unbroken run.
        var run: [SIMD2<Double>]=[]
        for step in stride(from: 0.0, through: 360, by: 2) {
            let placed=place(altitude: 0, azimuth: pose.azimuth+180+step, pose: pose, width: width, height: height, fieldOfView: fieldOfView, clipped: false)
            if let p=placed.point, abs(p.x-width/2)<width*8, abs(p.y-height/2)<height*8 { run.append(p) }
        }
        let zenith=SIMD3<Double>(0, 0, 1)
        let toward=SIMD2(simd_dot(zenith, pose.right), -simd_dot(zenith, pose.up))
        guard run.count>=2, let first=run.first, let last=run.last, simd_length(toward)>1e-6 else { return nil }
        let far=simd_normalize(toward)*(width+height)*20
        return run+[last+far, first+far]
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
