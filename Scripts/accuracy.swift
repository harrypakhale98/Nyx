import Foundation

let parks=try JSONDecoder().decode([Park].self,from:Data(contentsOf:URL(fileURLWithPath:"Nyx/Resources/parks.json")))
struct Reference:Decodable { let park:String;let date:String;let reference:Response }
struct Response:Decodable { struct Properties:Decodable { struct Info:Decodable { struct Event:Decodable { let phen:String;let time:String };let sundata:[Event];let moondata:[Event] };let data:Info };let properties:Properties }
let references=try JSONDecoder().decode([Reference].self,from:Data(contentsOf:URL(fileURLWithPath:"Research/usno-reference.json")))
let engine=AstronomyEngine()
var sunErrors:[Double]=[],moonErrors:[Double]=[],rows:[String]=[]
for ref in references {
    guard let park=parks.first(where:{$0.id==ref.park}) else { continue }
    let f=DateFormatter();f.timeZone=park.timeZone;f.dateFormat="yyyy-MM-dd HH:mm"
    guard let day=f.date(from:ref.date+" 12:00") else { continue }
    let night=engine.conditions(for:park,on:day),prev=engine.conditions(for:park,on:park.date(day,addingDays:-1))
    for event in ref.reference.properties.data.sundata {
        let time=event.phen=="Rise" ? prev.sunrise : event.phen=="Set" ? night.sunset : event.phen=="End Civil Twilight" ? night.civilDusk : nil
        if let time,let actual=f.date(from:ref.date+" "+event.time) { let error=abs(time.timeIntervalSince(actual))/60;sunErrors.append(error);rows.append("| \(park.id) | \(ref.date) | Sun \(event.phen) | \(String(format:"%.2f",error)) |") }
    }
    for event in ref.reference.properties.data.moondata where ["Rise","Set"].contains(event.phen) {
        if let actual=f.date(from:ref.date+" "+event.time) {
            let candidates=(event.phen=="Rise" ? [prev.moonrise,night.moonrise] : [prev.moonset,night.moonset]).compactMap{$0}
            if let error=candidates.map({abs($0.timeIntervalSince(actual))/60}).min() { moonErrors.append(error);rows.append("| \(park.id) | \(ref.date) | Moon \(event.phen) | \(String(format:"%.2f",error)) |") }
        }
    }
}
print("# Measured astronomy accuracy\n\n2026-10-02. Independent USNO fixtures, representative NPS coordinates. Absolute error in minutes. NOAA solar equations; truncated Meeus lunar position. Actual terrain and atmosphere can cause larger deviations.\n")
print("| Algorithm | Samples | Maximum error | Gate |\n|---|---:|---:|---:|")
print("| Solar rise/set/civil dusk | \(sunErrors.count) | \(String(format:"%.2f",sunErrors.max() ?? 0)) min | 2 min |")
print("| Lunar rise/set | \(moonErrors.count) | \(String(format:"%.2f",moonErrors.max() ?? 0)) min | 15 min |")
print("\n| Park | Date | Event | Error, min |\n|---|---|---|---:|\n"+rows.joined(separator:"\n"))
print("\nSources: [USNO API](https://aa.usno.navy.mil/data/api.html), [NOAA equations](https://gml.noaa.gov/grad/solcalc/calcdetails.html). Raw fixtures are in usno-reference.json. These fixtures independently validate sunrise, sunset, and civil dusk. Astronomical twilight uses the same coordinates at −18° but has no independent published fixture here; do not claim it is measured to two minutes.\n")
