import Testing
@testable import SportlyCore

struct ChannelSteppingTests {
    let ids = ["a", "b", "c"]
    @Test func wrapsForward() {
        #expect(ChannelStepping.neighbor(of: "b", in: ids, offset: 1) == "c")
        #expect(ChannelStepping.neighbor(of: "c", in: ids, offset: 1) == "a")
    }
    @Test func wrapsBackward() {
        #expect(ChannelStepping.neighbor(of: "b", in: ids, offset: -1) == "a")
        #expect(ChannelStepping.neighbor(of: "a", in: ids, offset: -1) == "c")
    }
    @Test func unknownStartsAtEnds() {
        #expect(ChannelStepping.neighbor(of: "z", in: ids, offset: 1) == "a")
        #expect(ChannelStepping.neighbor(of: nil, in: ids, offset: -1) == "c")
    }
    @Test func emptyIsNil() {
        #expect(ChannelStepping.neighbor(of: "a", in: [], offset: 1) == nil)
    }
    @Test func singleChannelStaysPut() {
        #expect(ChannelStepping.neighbor(of: "a", in: ["a"], offset: 1) == "a")
    }
}
