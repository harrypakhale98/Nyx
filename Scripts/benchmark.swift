// Development-only optimized CPU benchmark. Run from the repository root:
// task_dir=$(mktemp -d /tmp/nyx-benchmark.XXXXXX)
// cp Scripts/benchmark.swift "$task_dir/main.swift"
// swiftc -O Nyx/Models/Park.swift Nyx/Models/SkyConditions.swift \
//   Nyx/Services/AstronomyEngine.swift Nyx/Services/ScoreEngine.swift \
//   "$task_dir/main.swift" -o "$task_dir/benchmark"
// "$task_dir/benchmark"
import Foundation
let parks=try JSONDecoder().decode([Park].self,from:Data(contentsOf:URL(fileURLWithPath:"Nyx/Resources/parks.json")))
let date=Date(timeIntervalSince1970:1790971200)
let engine=AstronomyEngine(),scoring=ScoreEngine(),clock=ContinuousClock()
var checksum=0
let elapsed=clock.measure {
    for park in parks { for offset in 0..<14 {
        let sky=engine.conditions(for:park,on:park.date(date,addingDays:offset))
        checksum+=scoring.score(sky:sky,bortle:park.bortleEstimate,cloudCover:nil).value
    } }
}
let c=elapsed.components
let seconds=Double(c.seconds)+Double(c.attoseconds)/1e18
print("macOS optimized engine, 882 nights: \(seconds) seconds; checksum \(checksum)")
