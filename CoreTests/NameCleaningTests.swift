import Testing
@testable import SportlyCore

struct NameCleaningTests {
    @Test func stripsRegionPrefixesQualityAndRawMarkers() {
        #expect(NameCleaning.local("US| ESPN 2 FHD ᴿᴬᵂ") == "ESPN 2")
        #expect(NameCleaning.local("|UK| Sky Sports Main Event HD") == "Sky Sports Main Event")
        #expect(NameCleaning.local("UK: BBC One (B)") == "BBC One")
        #expect(NameCleaning.local("CA - TSN 4 4K") == "TSN 4")
        #expect(NameCleaning.local("[FR] Canal+ Sport HEVC") == "Canal+ Sport")
    }

    @Test func keepsLeagueEventPrefixesAndNumbers() {
        // "NBA" is not a region code: event labels stay as they are.
        #expect(NameCleaning.local("NBA | 01 - Lakers vs Celtics") == "NBA | 01 - Lakers vs Celtics")
        #expect(NameCleaning.local("ESPN 2") == "ESPN 2")
        #expect(NameCleaning.local("HDNet Movies") == "HDNet Movies")
    }

    @Test func neverReturnsAnEmptyName() {
        #expect(NameCleaning.local("HD") == "HD")
        #expect(NameCleaning.local("  US|  ") == "US")
    }

    @Test func flagsLeftoversForTheModel() {
        #expect(NameCleaning.needsModel("ESPN 2") == false)
        #expect(NameCleaning.needsModel("Sky Sports Main Event") == false)
        #expect(NameCleaning.needsModel("FOX SPORTS 1"))
        #expect(NameCleaning.needsModel("beIN ★ Sports"))
    }

    @Test func proposalsMustComeFromTheOriginal() {
        #expect(NameCleaning.validate(raw: "FOX SPORTS 1", proposed: "Fox Sports 1") == "Fox Sports 1")
        #expect(NameCleaning.validate(raw: "beIN ★ Sports", proposed: "beIN Sports") == "beIN Sports")
        #expect(NameCleaning.validate(raw: "FOX SPORTS 1", proposed: "Fox Sports 2") == nil)
        #expect(NameCleaning.validate(raw: "FOX SPORTS 1", proposed: "FOX Sports Network 1") == nil)
        #expect(NameCleaning.validate(raw: "ESPN", proposed: "   ") == nil)
    }
}
