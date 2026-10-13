import Foundation
import SwiftUI
import Testing
@testable import Nyx

/// iPhone Duo: its two displays' widths, the fold's place in two-column pages, and where a night drags.
@Suite struct IPhoneDuoTests {
    // MARK: Widths, never the device

    @Test func innerDisplayInLandscapeTakesTwoColumns() {
        // Inner display in landscape: 951 pt less the side bar (about 70) still splits.
        #expect(WideLayout.columns(width:880,largeText:false)==2)
        #expect(ParksTab.split(width:880,largeText:false))
        // Inner display in portrait (669 pt) and the outer display (466 pt, 678 in landscape) keep one column.
        for width in [669.0,466,678,400] { #expect(WideLayout.columns(width:width,largeText:false)==1) }
        // Field mode puts the night beside the sky in landscape only.
        #expect(WideLayout.sideBySide(width:880,height:669,largeText:false))
        #expect(!WideLayout.sideBySide(width:669,height:880,largeText:false))
    }
    @Test func largeIPhonesInLandscapeKeepOneColumn() {
        // 956 pt less both sides' safe areas, and 11-inch iPad portrait, stay single.
        #expect(WideLayout.columns(width:832,largeText:false)==1)
        #expect(WideLayout.columns(width:834,largeText:false)==1)
        #expect(WideLayout.columns(width:WideLayout.twoColumnWidth-1,largeText:false)==1)
    }

    @Test func fieldModeSitsSideBySideInPhoneLandscape() {
        // An iPhone in landscape (about 750 by 402 inside its safe areas) and the Duo's outer display
        // turned (678 less its side bar): the night beside where to look, no page switch.
        #expect(WideLayout.sideBySide(width:750,height:402,largeText:false,compactHeight:true))
        #expect(WideLayout.sideBySide(width:605,height:466,largeText:false,compactHeight:true))
        // Not narrower than 600, not at accessibility sizes, never in portrait.
        #expect(!WideLayout.sideBySide(width:560,height:320,largeText:false,compactHeight:true))
        #expect(!WideLayout.sideBySide(width:750,height:402,largeText:true,compactHeight:true))
        #expect(!WideLayout.sideBySide(width:402,height:750,largeText:false,compactHeight:true))
        // A regular-height window of the same width keeps one page at a time.
        #expect(!WideLayout.sideBySide(width:750,height:600,largeText:false))
    }

    // MARK: The fold

    @Test func bookFoldPlacesTheGap() throws {
        // A 28-point fold down the middle of an 880-point page.
        let fold=Fold(frame:CGRect(x:426,y:0,width:28,height:669))
        #expect(fold.dividesWidth)
        #expect(fold.leadingWidth(in:880)==426)
        let split=ColumnSplit.widths(total:880,narrow:.trailing,narrowMax:500,spacing:36,fold:fold)
        // Each column ends half the spacing short of the fold, so the gap is the fold and the spacing.
        #expect(split.leading==408)
        #expect(split.trailing==408)
        #expect(split.gap==64)
        #expect(split.leading+split.gap+split.trailing==880)
    }
    @Test func scrollingPastTheFoldLeavesItUnchanged() {
        // In a scrolling page the fold's region moves up and down the page's coordinates with every
        // frame; the fold the columns read must not change, or they would re-lay on each frame.
        let atTop=Fold(frame:CGRect(x:426.3,y:0,width:27.6,height:669))
        let scrolled=Fold(frame:CGRect(x:426.3,y:-1840.5,width:27.6,height:3200))
        #expect(atTop==scrolled)
        // Whole points, rounded outward so the gap always covers the crease.
        #expect(atTop.minX==426)
        #expect(atTop.maxX==454)
        // A side-to-side fold keeps no position at all, so it is equal wherever it is.
        #expect(Fold(frame:CGRect(x:0,y:466,width:669,height:28))==Fold(frame:CGRect(x:0,y:-300,width:669,height:28)))
    }
    #if DEBUG
    @Test func columnsScrolledOffKeepTheFold() throws {
        // The stand-in fold (and perhaps hardware's) is clipped to what is on screen. Read inside the
        // scrolling content, columns nearly scrolled off the top see a sliver wider than tall (a
        // side-to-side fold), and columns wholly off see none: either way they sprang back mid-scroll.
        let window=CGSize(width:880,height:669)
        let band=CGRect(x:426,y:0,width:28,height:669)
        let sliver=Fold.standIn(band:band,viewFrame:CGRect(x:24,y:-890,width:832,height:900),window:window)
        #expect(sliver?.dividesWidth==false)
        #expect(Fold.standIn(band:band,viewFrame:CGRect(x:24,y:-1900,width:832,height:900),window:window)==nil)
        // Read on the scroll view's own frame (`foldSource`), which never leaves the screen, the fold is
        // whole at every scroll offset; the columns move it by their leading edge only.
        let page=try #require(Fold.standIn(band:band,viewFrame:CGRect(origin:.zero,size:window),window:window))
        #expect(page.dividesWidth)
        let inColumns=page.seen(fromX:24)
        #expect(inColumns.minX==402)
        #expect(inColumns.maxX==430)
        let split=ColumnSplit.widths(total:832,narrow:.trailing,narrowMax:500,spacing:36,fold:inColumns)
        #expect(split.leading==384)
        #expect(split.trailing==384)
        #expect(split.gap==64)
        // A side-to-side fold has no place to move.
        let table=Fold(frame:CGRect(x:0,y:320,width:880,height:28))
        #expect(table.seen(fromX:24)==table)
    }
    #endif
    @Test func parkBesideTheListStartsPastTheFold() {
        // Half open like a book: the floating sidebar starts 10 points in from the tab, so the list is 10
        // narrower than the fold's near edge and ends on it; the park column starts there and keeps the
        // fold's width clear, so neither its margin nor its Back button sits on the crease.
        let fold=Fold(frame:CGRect(x:426,y:0,width:28,height:669))
        let list=ParksTab.listWidth(fold:fold,width:880,sidebarMargin:10)
        #expect(list==416)
        #expect((list ?? 0)+10==fold.minX)
        #expect(ParksTab.listWidth(fold:fold,width:880,sidebarMargin:0)==426)
        // Flat, or a fold too near an edge for the list to reach: the column keeps its usual widths.
        #expect(ParksTab.listWidth(fold:nil,width:880,sidebarMargin:10)==nil)
        #expect(ParksTab.listWidth(fold:Fold(frame:CGRect(x:300,y:0,width:28,height:669)),width:880,sidebarMargin:10)==nil)
    }
    @Test func tableFoldAndNarrowSidesLeaveColumnsAlone() {
        // A fold side to side (a Duo standing like a laptop) does not divide the width.
        let table=Fold(frame:CGRect(x:0,y:466,width:669,height:28))
        #expect(!table.dividesWidth)
        #expect(table.leadingWidth(in:669)==nil)
        let unfolded=ColumnSplit.widths(total:880,narrow:.trailing,narrowMax:500,spacing:36,fold:nil)
        #expect(ColumnSplit.widths(total:880,narrow:.trailing,narrowMax:500,spacing:36,fold:table)==unfolded)
        // A fold near an edge (another app beside Nyx, or a page that is mostly on one half) is ignored.
        let nearEdge=Fold(frame:CGRect(x:120,y:0,width:28,height:669))
        #expect(nearEdge.leadingWidth(in:880)==nil)
        #expect(ColumnSplit.widths(total:880,narrow:.trailing,narrowMax:500,spacing:36,fold:nearEdge)==unfolded)
    }
    @Test func unfoldedColumnsKeepTheirMeasure() {
        // Tonight: the trailing column at most 500 points; Trip planner: the leading at most 420.
        let tonight=ColumnSplit.widths(total:1240,narrow:.trailing,narrowMax:500,spacing:36,fold:nil)
        #expect(tonight.trailing==500)
        #expect(tonight.leading==1240-36-500)
        let planner=ColumnSplit.widths(total:880,narrow:.leading,narrowMax:420,spacing:32,fold:nil)
        #expect(planner.leading==420)
        #expect(planner.trailing==880-32-420)
        // Narrower than twice the measure, the narrow column takes half.
        let half=ColumnSplit.widths(total:700,narrow:.trailing,narrowMax:500,spacing:36,fold:nil)
        #expect(half.trailing==332)
        #expect(half.leading==332)
    }

    // MARK: Dragging a night

    @Test func nightsDragWhereThereIsRoomToDrop() {
        // iPad in any window, and iPhone Duo's open inner display (regular both ways).
        #expect(NightDragPolicy.drags(pad:true,horizontal:.compact,vertical:.regular))
        #expect(NightDragPolicy.drags(pad:false,horizontal:.regular,vertical:.regular))
        // An iPhone's single screen, a large iPhone in landscape (regular by compact) and the outer display.
        #expect(!NightDragPolicy.drags(pad:false,horizontal:.compact,vertical:.regular))
        #expect(!NightDragPolicy.drags(pad:false,horizontal:.regular,vertical:.compact))
        #expect(!NightDragPolicy.drags(pad:false,horizontal:.compact,vertical:.compact))
    }
}
