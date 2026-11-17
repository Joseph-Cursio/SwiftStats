import AllKinds
import Testing

@Test func areaOfSquare() {
    #expect(Square(side: 3).area == 9)
}

@Suite struct SquareSuite {
    @Test("perimeter") func perimeter() {
        #expect(Square(side: 1).perimeter == 4)
    }

    func makeSquare() -> Square { Square(side: 5) }
}
