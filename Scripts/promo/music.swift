// Original ambient score for the Nyx promo, synthesized from scratch (no samples, no third-party audio).
// swift music.swift out.m4a  : 48 kHz stereo AAC, length and cue points match the edit.
import AVFoundation
import Foundation

let sr = 48000.0
let total = 37.5
let n = Int(total * sr)
var L = [Float](repeating: 0, count: n), R = [Float](repeating: 0, count: n)

// Cuts in the edit; each starts a chord and rings a chime.
let cuts: [Double] = [0, 3.4, 7.4, 11.9, 16.9, 20.9, 24.9, 28.9, 32.9]
func midi(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }
// D major, voiced wide and open. Last chord resolves home.
let chords: [[Double]] = [
    [50, 57, 64, 66, 69],        // Dmaj9 (D A E F# A)
    [47, 54, 61, 62, 66],        // Bm9 (B F# C# D F#)
    [43, 50, 57, 61, 66],        // Gmaj7#11-ish (G D A C# F#)
    [45, 52, 59, 64, 71],        // Aadd9 (A E B E B)
    [42, 49, 57, 61, 64],        // F#m7 (F# C# A C# E)
    [43, 50, 59, 62, 66],        // Gmaj9
    [40, 47, 55, 59, 62],        // Em9 (night, red)
    [45, 52, 57, 59, 64],        // Asus2
    [38, 50, 57, 64, 66, 69],    // Dmaj9, low D: home
]
func env(_ t: Double, start: Double, end: Double, attack: Double, release: Double) -> Double {
    if t < start || t > end + release { return 0 }
    let a = min(1, (t - start) / attack)
    let r = t > end ? max(0, 1 - (t - end) / release) : 1
    return a * a * (3 - 2 * a) * r
}

// Pads: each chord tone as three slightly detuned voices with a few soft harmonics, panned across.
for (ci, chord) in chords.enumerated() {
    let start = cuts[ci] - (ci == 0 ? 0 : 0.6)
    let end = ci + 1 < cuts.count ? cuts[ci + 1] : total - 2.6
    let release = ci + 1 < cuts.count ? 1.8 : 2.4
    let s0 = max(0, Int(start * sr)), s1 = min(n, Int((end + release) * sr))
    for (vi, note) in chord.enumerated() {
        let pan = Double(vi) / Double(max(1, chord.count - 1)) * 1.4 - 0.7
        let gl = Float(sqrt(0.5 * (1 - pan))), gr = Float(sqrt(0.5 * (1 + pan)))
        let vol = (note < 48 ? 0.16 : 0.085) * (ci == chords.count - 1 ? 1.15 : 1)
        for d in [-0.07, 0.0, 0.06] {
            let f = midi(note + d)
            var ph = Double(vi) * 0.7 + d * 10
            for i in s0..<s1 {
                let t = Double(i) / sr
                let e = env(t, start: start, end: end, attack: ci == 0 ? 2.4 : 1.4, release: release)
                if e == 0 { ph += 2 * .pi * f / sr; continue }
                // Slow breathing in brightness.
                let bright = 0.35 + 0.2 * sin(2 * .pi * t / 9 + Double(vi))
                let v = sin(ph) + bright * 0.5 * sin(2 * ph) + bright * 0.22 * sin(3 * ph)
                let s = Float(v * e * vol / 3)
                L[i] += s * gl; R[i] += s * gr
                ph += 2 * .pi * f / sr
            }
        }
    }
}

// Glass plucks: a slow rising arpeggio from the chord, from the second shot on, quiet.
func pluck(at t0: Double, note: Double, vol: Double, pan: Double, decay: Double = 1.6) {
    let f = midi(note)
    let s0 = Int(t0 * sr), len = Int(decay * 3 * sr)
    let gl = Float(sqrt(0.5 * (1 - pan))), gr = Float(sqrt(0.5 * (1 + pan)))
    for k in 0..<len where s0 + k < n {
        let t = Double(k) / sr
        let e = exp(-t / decay) * min(1, t / 0.004)
        let v = sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * 2 * f * t) * exp(-t / 0.4) + 0.12 * sin(2 * .pi * 3.01 * f * t) * exp(-t / 0.2)
        let s = Float(v * e * vol)
        L[s0 + k] += s * gl; R[s0 + k] += s * gr
    }
}
let beat = 60.0 / 70.0
for ci in 1..<(chords.count - 1) {
    let tones = chords[ci].suffix(4).map { $0 + 12 }
    var t = cuts[ci] + beat / 2
    var k = 0
    let end = cuts[ci + 1] - 0.15
    while t < end {
        let note = tones[[0, 1, 2, 3, 2, 1][k % 6]]
        pluck(at: t, note: note, vol: 0.045 + (ci >= 6 ? -0.01 : 0), pan: [-0.5, 0.2, 0.6, -0.2][k % 4])
        t += beat / 2; k += 1
    }
}

// Chimes at each cut: inharmonic bell partials, high and soft; a fuller one for the final card.
func bell(at t0: Double, note: Double, vol: Double, pan: Double) {
    let f = midi(note)
    let partials: [(Double, Double, Double)] = [(1, 1, 2.6), (2.0, 0.45, 1.6), (2.76, 0.35, 1.1), (5.4, 0.18, 0.6), (8.93, 0.08, 0.35)]
    let s0 = Int(t0 * sr), len = Int(6 * sr)
    let gl = Float(sqrt(0.5 * (1 - pan))), gr = Float(sqrt(0.5 * (1 + pan)))
    for k in 0..<len where s0 + k < n {
        let t = Double(k) / sr
        var v = 0.0
        for (m, a, d) in partials { v += a * sin(2 * .pi * f * m * t) * exp(-t / d) }
        let s = Float(v * vol * min(1, t / 0.003))
        L[s0 + k] += s * gl; R[s0 + k] += s * gr
    }
}
let chimeNotes: [Double] = [81, 78, 81, 83, 76, 78, 74, 76, 81]
for (i, c) in cuts.enumerated() where i > 0 { bell(at: c - 0.05, note: chimeNotes[i], vol: i == cuts.count - 1 ? 0.09 : 0.05, pan: i % 2 == 0 ? 0.35 : -0.35) }
bell(at: 33.6, note: 86, vol: 0.05, pan: 0.0)
bell(at: 34.4, note: 90, vol: 0.04, pan: 0.3)

// Starlight: rare, very soft high pings, seeded so every render is the same.
var seed: UInt64 = 7
func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
var tt = 1.0
while tt < total - 3 {
    pluck(at: tt, note: [93, 95, 97, 100, 102][Int(rnd() * 5)], vol: 0.012, pan: rnd() * 1.6 - 0.8, decay: 0.9)
    tt += 0.9 + rnd() * 1.8
}

// Reverb (Schroeder/Freeverb style): parallel combs and series allpasses per channel.
func reverb(_ x: [Float], offset: Int) -> [Float] {
    let combs = [1557, 1617, 1491, 1422, 1277, 1356].map { $0 * 2 + offset }
    var out = [Float](repeating: 0, count: x.count)
    for d in combs {
        var buf = [Float](repeating: 0, count: d); var idx = 0; var lp: Float = 0
        for i in 0..<x.count {
            let y = buf[idx]
            lp = y * 0.6 + lp * 0.4
            buf[idx] = x[i] + lp * 0.86
            idx = (idx + 1) % d
            out[i] += y
        }
    }
    for d in [556, 441, 341].map({ $0 * 2 + offset / 2 }) {
        var buf = [Float](repeating: 0, count: d); var idx = 0
        for i in 0..<out.count {
            let b = buf[idx]; let y = -out[i] + b
            buf[idx] = out[i] + b * 0.5
            idx = (idx + 1) % d
            out[i] = y
        }
    }
    return out.map { $0 / Float(combs.count) }
}
let wl = reverb(L, offset: 0), wr = reverb(R, offset: 46)
var mix = [Float](repeating: 0, count: n * 2)
var peak: Float = 0
for i in 0..<n {
    let t = Double(i) / sr
    let fade = Float(min(1, t / 1.2) * min(1, max(0, (total - t) / 2.5)))
    let l = tanh((L[i] * 0.7 + wl[i] * 0.55) * 1.4) * fade
    let r = tanh((R[i] * 0.7 + wr[i] * 0.55) * 1.4) * fade
    mix[2 * i] = l; mix[2 * i + 1] = r
    peak = max(peak, abs(l), abs(r))
}
let gain = 0.89 / peak  // about -1 dBFS
let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
pcm.frameLength = AVAudioFrameCount(n)
for i in 0..<n { pcm.floatChannelData![0][i] = mix[2 * i] * gain; pcm.floatChannelData![1][i] = mix[2 * i + 1] * gain }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
do {
    // Scoped, so the file is closed (and the AAC finalized) before the program ends.
    let file = try AVAudioFile(forWriting: out, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256000])
    try file.write(from: pcm)
}
print("wrote", out.path, String(format: "peak %.3f -> gain %.2f", peak, gain))
