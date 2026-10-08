import Foundation
import Testing
@testable import Nyx

/// Counted strings are real String Catalog plural variations (Research/localization/en-plurals.json and
/// es-plurals.json), so "1 night" and "2 nights" are one catalog key each and Spanish never prints "1 noches".
struct PluralTests {
    typealias Case = (value:String.LocalizationValue, expected:String)
    /// One catalog string in one language, read from the app bundle so the device language does not matter.
    func text(_ value:String.LocalizationValue,_ language:String) -> String {
        String(localized:LocalizedStringResource(value,locale:Locale(identifier:language),bundle:.atURL(Bundle.main.bundleURL)))
    }
    func check(_ cases:[Case],_ language:String) {
        for item in cases { #expect(text(item.value,language)==item.expected,"\(language): \(item.expected)") }
    }

    @Test func oneAndOtherInEnglish() {
        check([
            ("\(1) nights","1 night"), ("\(2) nights","2 nights"),
            ("\(1) national parks","1 national park"), ("\(1) sites","1 site"),
            ("About \(1) hours of true darkness","About 1 hour of true darkness"),
            ("About \(9) hours of true darkness","About 9 hours of true darkness"),
            ("\(1) parks have a closure.","1 park has a closure."), ("\(4) parks have a closure.","4 parks have a closure."),
        ],"en")
    }
    @Test func oneAndOtherInSpanish() {
        check([
            ("\(1) nights","1 noche"), ("\(3) nights","3 noches"),
            ("\(1) national parks","1 parque nacional"),
            ("About \(1) hours of true darkness","Cerca de 1 hora de oscuridad total"),
            ("About \(9) hours of true darkness","Cerca de 9 horas de oscuridad total"),
            ("\(1) parks have a closure.","1 parque tiene un cierre."), ("\(4) parks have a closure.","4 parques tienen un cierre."),
            ("At \(1) seconds: \("Hum")","Al segundo 1: Hum"), ("At \(5) seconds: \("Hum")","A los 5 segundos: Hum"),
        ],"es")
    }
    /// The count is not the first argument: the string's other arguments keep their places.
    @Test func countsAfterOtherArguments() {
        let today="Today", zion="Zion"
        check([("\(today) · \(1) parks tonight","Today · 1 park tonight")],"en")
        check([
            ("\(today) · \(7) parks tonight","Today · 7 parques esta noche"),
            ("\(1) nights at \(zion)","1 noche en Zion"),
            ("Add \(2) nights at \(zion) to Calendar","Agregar 2 noches en Zion a Calendario"),
        ],"es")
    }
    /// Two or three counts in one sentence each get their own form.
    @Test func severalCountsInOneString() {
        check([
            ("\(1) nights under the stars at \(1) national parks","1 night under the stars at 1 national park"),
            ("\(12) nights under the stars at \(3) national parks","12 nights under the stars at 3 national parks"),
            ("Your constellation: \(1) nights at \(1) parks across \(1) seasons, each a star at its park on a map of the United States.",
             "Your constellation: 1 night at 1 park across 1 season, each a star at its park on a map of the United States."),
            ("\(1) nights, at most \(7)","1 night, at most 7"),
        ],"en")
        check([
            ("\(1) nights under the stars at \(3) national parks","1 noche bajo las estrellas en 3 parques nacionales"),
            ("\(5) nights under the stars at \(1) national parks","5 noches bajo las estrellas en 1 parque nacional"),
            ("Your constellation: \(8) nights at \(2) parks across \(3) seasons, each a star at its park on a map of the United States.",
             "Tu constelación: 8 noches en 2 parques a lo largo de 3 estaciones, cada una como una estrella en su parque sobre un mapa de Estados Unidos."),
            ("\(3) nights, at most \(7)","3 noches, como máximo 7"),
        ],"es")
    }
    /// A form may drop the number ("The park"); the other arguments still land in the right places.
    @Test func aFormThatDropsTheNumber() {
        let reach="within 200 mi", alcance="a menos de 200 mi"
        check([
            ("The \(1) parks with the darkest nights this week, of \(1) \(reach).","The park with the darkest nights this week, of 1 within 200 mi."),
            ("The \(4) parks with the darkest nights this week, of \(9) \(reach).","The 4 parks with the darkest nights this week, of 9 within 200 mi."),
            ("Best of the next \(1) nights","Best of the next 1 night"),
        ],"en")
        check([
            ("The \(1) parks with the darkest nights this week, of \(6) \(alcance).","El parque con las noches más oscuras de esta semana, de 6 a menos de 200 mi."),
            ("Best of the next \(1) nights","La mejor de la próxima noche"),
            ("Best of the next \(14) nights","La mejor de las próximas 14 noches"),
            ("Number \(2) of the next \(1) nights","Número 2 de la próxima noche"),
        ],"es")
    }
}
