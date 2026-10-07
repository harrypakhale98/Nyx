import Foundation
import Testing
@testable import Nyx

/// A stand-in for the system's age signals: says whether an age range is required and how a request ends.
@MainActor final class FakeAgeSignals: AgeSignalSource {
    enum Answer { case shared, declined, error }
    let needs: AgeAssurance.Need
    let answer: Answer
    private(set) var requests=0
    init(_ needs: AgeAssurance.Need, answer: Answer = .shared) { self.needs=needs; self.answer=answer }
    func need() async -> AgeAssurance.Need { needs }
    func requestRange() async throws -> Bool {
        requests+=1
        switch answer { case .shared: return true; case .declined: return false; case .error: throw URLError(.notConnectedToInternet) }
    }
}

@MainActor @Suite("Compliance") struct ComplianceTests {
    @Test("Age range is requested only when the system says this account requires it")
    func asksOnlyWhenRequired() async {
        for need in [AgeAssurance.Need.notRequired, .unknown] {
            let source=FakeAgeSignals(need)
            #expect(await AgeAssurance.run(source) == .notRequired)
            #expect(source.requests == 0)
        }
        let required=FakeAgeSignals(.required)
        #expect(await AgeAssurance.run(required) == .shared)
        #expect(required.requests == 1)
    }

    @Test("A refusal or an error never blocks: each ends quietly")
    func refusalAndErrorsAreQuiet() async {
        #expect(await AgeAssurance.run(FakeAgeSignals(.required, answer: .declined)) == .declined)
        #expect(await AgeAssurance.run(FakeAgeSignals(.required, answer: .error)) == .failed)
    }

    @Test("Age gates follow the Texas categories, each range at least two years")
    func gates() {
        let g=AgeAssurance.gates
        let list: [Int]=[g.0, g.1, g.2]
        #expect(list == [13, 16, 18])
        #expect(g.1 - g.0 >= 2 && g.2 - g.1 >= 2)
    }

    @Test("Credit links open exactly the licensor pages in Safari")
    func creditLinks() {
        #expect(BrowserLink.openMeteo?.absoluteString == "https://open-meteo.com")
        #expect(BrowserLink.creativeCommonsBY?.absoluteString == "https://creativecommons.org/licenses/by/4.0/")
    }
}
