import Foundation
import Testing
@testable import Nyx

/// Ask Nyx's records under a checked answer: the cited ones first under their own numbers, the rest
/// folded, and one list whenever nothing real is cited.
struct GuideRecordOrderTests {
    @Test func citedRecordsLeadInTheModelsOrder() throws {
        let order=try #require(GuideRecords.order(count:11,citations:[7,2,7]))
        #expect(order.cited==[2,7])
        #expect(order.folded==[0,1,3,4,5,6,8,9,10])
    }
    @Test func citationsOutsideTheRecordsAreIgnored() throws {
        let order=try #require(GuideRecords.order(count:3,citations:[-1,1,3,99]))
        #expect(order.cited==[1])
        #expect(order.folded==[0,2])
        #expect(GuideRecords.order(count:3,citations:[-1,3,99])==nil,"Only missing records cited: one list")
    }
    @Test func nothingCitedKeepsOneList() {
        #expect(GuideRecords.order(count:5,citations:[])==nil)
        #expect(GuideRecords.order(count:0,citations:[0])==nil)
    }
    @Test func everyRecordCitedFoldsNothing() throws {
        let order=try #require(GuideRecords.order(count:3,citations:[0,1,2]))
        #expect(order.cited==[0,1,2])
        #expect(order.folded.isEmpty,"No disclosure when nothing is left to fold")
    }
    @Test func oneFoldedRecordIsSingular() throws {
        let order=try #require(GuideRecords.order(count:2,citations:[0]))
        #expect(order.folded.count==1)
        func text(_ value:String.LocalizationValue,_ language:String)->String {
            String(localized:LocalizedStringResource(value,locale:Locale(identifier:language),bundle:.atURL(Bundle.main.bundleURL)))
        }
        #expect(text("\(order.folded.count) other records","en")=="1 other record")
        #expect(text("\(order.folded.count) other records","es")=="1 registro más")
        #expect(text("\(3) other records","es")=="3 registros más")
    }
}
