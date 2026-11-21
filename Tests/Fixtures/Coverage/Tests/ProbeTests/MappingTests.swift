@testable import Exe
import Probe
import Testing

@Test func accessors() {
    var box = Box()
    #expect(box.both == 0)
    box.watched = 2
    #expect(box.storage == 3)
    #expect(box.doubled == 6)
    #expect(box.cached == 4)
    #expect(box[1] == 4)
}

@Test func wrappersAndCases() {
    #expect(Settings().level == 3)
    #expect(lefts([1, 2]).count == 2)
}

@Test func nesting() {
    #expect(outer(false) == 0)
    #expect(sameLine() == 2)
    #expect(anyLarge([]))
}

@Test func overloadsAndModes() {
    #expect(describe(1) == "int 1")
    #expect(mode() == "debug")
    #expect(platform() == "other")
    #expect(bomFirst() == 1)
    #expect(bomSecond() == 2)
}

@Test func attachedAndFiles() {
    #expect(globalValue == 42)
    #expect(withDefault() == 2)
    #expect(firstSecret() == 1)
    #expect(fromHelper() == 11)
    #expect(excludedHelper() == 3)
    #expect(generatedHelper() == 4)
    #expect(exeHelper(2) == 6)
}
