import Testing
@testable import GlowApp

private let percent = LevelBoxScale(minimum: 0, maximum: 100, step: 1)
/// A popover row's boxes: 208 pt across with 2 pt between, so each box is 11.125 pt wide.
private let row = LevelBoxGeometry(width: 208, gap: 2)

private func isClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000_1 }

@Test func sixteenBoxesLikeMacOS() {
    #expect(LevelBoxScale.boxCount == 16)
    #expect(percent.fills(at: 50).count == 16)
}

@Test func boundaryBoxFillsInProportionFromItsLeadingEdge() {
    let fills = percent.fills(at: 47)
    #expect(fills.prefix(7).allSatisfy { $0 == 1 })
    #expect(isClose(fills[7], 0.52))
    #expect(fills.dropFirst(8).allSatisfy { $0 == 0 })
}

@Test func emptyAndFullLevelsLightNoBoxesAndEveryBox() {
    #expect(percent.fills(at: 0).allSatisfy { $0 == 0 })
    #expect(percent.fills(at: 100).allSatisfy { $0 == 1 })
    // Readings outside the range draw as its ends, never as more than sixteen boxes.
    #expect(percent.fills(at: -20).allSatisfy { $0 == 0 })
    #expect(percent.fills(at: 140).allSatisfy { $0 == 1 })
}

@Test func fillsFollowTheRangeNotTheRawNumber() {
    let range = LevelBoxScale(minimum: 10, maximum: 90, step: 1)
    let fills = range.fills(at: 50)
    #expect(fills.prefix(8).allSatisfy { $0 == 1 })
    #expect(fills.dropFirst(8).allSatisfy { $0 == 0 })
    // A range with no width can't say where it is, so it draws empty.
    #expect(LevelBoxScale(minimum: 5, maximum: 5, step: 1).fills(at: 5).allSatisfy { $0 == 0 })
}

@Test func eachBoxIsASixteenthRoundedToTheSettingsStep() {
    #expect(percent.value(ofBoxes: 0) == 0)
    #expect(percent.value(ofBoxes: 1) == 6)
    #expect(percent.value(ofBoxes: 8) == 50)
    #expect(percent.value(ofBoxes: 10) == 63)
    #expect(percent.value(ofBoxes: 16) == 100)
    let fives = LevelBoxScale(minimum: 0, maximum: 100, step: 5)
    #expect(fives.value(ofBoxes: 1) == 5)
    #expect(fives.value(ofBoxes: 3) == 20)
}

@Test func clickingABoxLightsItAndEveryBoxBeforeIt() {
    #expect(percent.valueForClick(onBox: 8, current: 30) == 50)
    #expect(percent.valueForClick(onBox: 3, current: 50) == 19)
    // A box only partly lit fills up rather than stepping down.
    #expect(percent.valueForClick(onBox: 8, current: 47) == 50)
    #expect(percent.valueForClick(onBox: 16, current: 0) == 100)
}

@Test func clickingTheTopLitBoxAgainStepsDownOne() {
    #expect(percent.valueForClick(onBox: 8, current: 50) == 44)
    #expect(percent.valueForClick(onBox: 16, current: 100) == 94)
    // So the lowest level is a click on the first box away.
    #expect(percent.valueForClick(onBox: 1, current: 6) == 0)
    #expect(percent.valueForClick(onBox: 1, current: 0) == 6)
}

@Test func steppingDownOnAShortRangeSkipsBoxesThatShareAValue() {
    // Eleven values over sixteen boxes: boxes 1 and 2 both round to 1.
    let short = LevelBoxScale(minimum: 0, maximum: 10, step: 1)
    #expect(short.value(ofBoxes: 1) == 1)
    #expect(short.value(ofBoxes: 2) == 1)
    #expect(short.valueForClick(onBox: 2, current: 1) == 0)
    #expect(short.stepped(1, by: 1) == 2)
}

@Test func arrowsAndVoiceOverMoveOneBoxEdgeAtATime() {
    #expect(percent.stepped(47, by: 1) == 50)
    #expect(percent.stepped(47, by: -1) == 44)
    #expect(percent.stepped(50, by: 1) == 56)
    #expect(percent.stepped(50, by: 2) == 63)
    #expect(percent.stepped(50, by: -2) == 38)
    // The ends hold.
    #expect(percent.stepped(100, by: 1) == 100)
    #expect(percent.stepped(0, by: -1) == 0)
    #expect(percent.stepped(98, by: 1) == 100)
    #expect(percent.stepped(2, by: -1) == 0)
}

@Test func dragPositionsLandOnTheSettingsStep() {
    #expect(percent.value(atFraction: 0.473) == 47)
    #expect(percent.value(atFraction: 1.2) == 100)
    #expect(percent.value(atFraction: -0.1) == 0)
    #expect(LevelBoxScale(minimum: 0, maximum: 100, step: 5).value(atFraction: 0.47) == 45)
}

@Test func boxesShareTheWidthAfterTheGaps() {
    #expect(isClose(row.boxWidth, 11.125))
    #expect(row.minX(of: 0) == 0)
    #expect(isClose(row.minX(of: 1), 13.125))
    #expect(isClose(row.minX(of: 15) + row.boxWidth, 208))
    #expect(LevelBoxGeometry(width: 10, gap: 2).boxWidth == 0)
}

@Test func aPointHitsTheBoxDrawnUnderIt() {
    for index in 0..<16 {
        #expect(row.box(at: row.minX(of: index) + row.boxWidth / 2) == index)
        #expect(row.box(at: row.minX(of: index)) == index)
        #expect(row.box(at: row.minX(of: index) + row.boxWidth - 0.01) == index)
    }
}

@Test func aPointInAGapBelongsToTheNearerBox() {
    let gapStart = row.minX(of: 3) + row.boxWidth
    #expect(row.box(at: gapStart + 0.9) == 3)
    #expect(row.box(at: gapStart + 1.1) == 4)
    // Past either end, the end box.
    #expect(row.box(at: -6) == 0)
    #expect(row.box(at: 208) == 15)
    #expect(row.box(at: 400) == 15)
}

@Test func aDragFillsTheBoxesUpToThePointer() {
    #expect(row.fraction(at: 0) == 0)
    #expect(row.fraction(at: 208) == 1)
    #expect(row.fraction(at: -10) == 0)
    #expect(row.fraction(at: 300) == 1)
    #expect(isClose(row.fraction(at: row.minX(of: 7) + row.boxWidth / 2), 7.5 / 16))
    // A gap is the end of the box before it.
    #expect(isClose(row.fraction(at: row.minX(of: 3) + row.boxWidth + 1), 4.0 / 16))
}

@Test func whereADragStopsIsWhereTheFillEnds() {
    // Halfway into the eighth box sets the level whose eighth box is half full.
    let x = row.minX(of: 7) + row.boxWidth / 2
    let level = percent.value(atFraction: row.fraction(at: x))
    let fills = percent.fills(at: level)
    #expect(level == 47)
    #expect(fills[6] == 1)
    #expect(fills[7] > 0 && fills[7] < 1)
    #expect(row.box(at: x) == 7)
}
