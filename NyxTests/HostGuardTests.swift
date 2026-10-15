import Foundation
import Testing
@testable import Nyx

/// Nyx reaches four hosts and nothing else. A redirect could hand a request to any server, so
/// `HostGuard` refuses every one, whatever the status and wherever it points, even back to an
/// allowed host. Called directly with a task that never runs: nothing here touches the network.
struct HostGuardTests {
    @Test func everyRedirectIsRefused() throws {
        let session=URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let from=try #require(URL(string: "https://api.open-meteo.com/v1/forecast"))
        let task=session.dataTask(with: from)
        let hostGuard=HostGuard()
        let redirects=[(301, "https://elsewhere.invalid/forecast"), (302, "https://api.open-meteo.com/v1/forecast?moved=1"),
                       (303, "http://developer.nps.gov/api/v1/alerts"), (307, "https://air-quality-api.open-meteo.com/v1/air-quality"),
                       (308, "https://developer.nps.gov.elsewhere.invalid/api/v1/events"), (302, "https://services.swpc.noaa.gov/products/noaa-scales.json")]
        for (status, target) in redirects {
            let to=try #require(URL(string: target))
            let response=try #require(HTTPURLResponse(url: from, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": target]))
            var answered=0
            var followed: URLRequest?=URLRequest(url: to)
            hostGuard.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: to)) { request in
                answered+=1
                followed=request
            }
            #expect(answered == 1, "Status \(status) to \(target) was not answered exactly once")
            #expect(followed == nil, "Status \(status) to \(target) was followed")
        }
    }
}
