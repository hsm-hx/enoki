import XCTest
@testable import EnokiCore

final class LocalDialogueProviderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func conversation(_ id: String, _ category: DialogueCategory, cooldown: TimeInterval = 3600) -> Conversation {
        Conversation(id: id, category: category, cooldown: cooldown,
                     lines: [DialogueLine(speaker: .saku, text: id)])
    }

    private func makeProvider() -> LocalDialogueProvider {
        let set = DialogueSet(conversations: [
            conversation("water_1", .water),
            conversation("water_2", .water),
            conversation("break_1", .break),
            conversation("ambient_1", .ambient),
            conversation("pair_1", .pair),
        ])
        let provider = LocalDialogueProvider(dialogueSet: set)
        provider.randomIndex = { _ in 0 }   // 常に先頭
        return provider
    }

    private func context(allowed: Set<DialogueCategory>,
                         recent: [String] = [],
                         lastCategory: DialogueCategory? = nil,
                         lastShownAt: [String: Date] = [:],
                         trigger: ConversationContext.Trigger = .scheduled) -> ConversationContext {
        ConversationContext(now: now,
                            allowedCategories: allowed,
                            recentlyShownIDs: recent,
                            lastCategory: lastCategory,
                            lastShownAt: lastShownAt,
                            trigger: trigger)
    }

    func testFiltersByAllowedCategories() {
        let provider = makeProvider()
        XCTAssertEqual(provider.pick(context: context(allowed: [.break]))?.id, "break_1")
        XCTAssertNil(provider.pick(context: context(allowed: [.lunch])))
        XCTAssertNil(provider.pick(context: context(allowed: [])))
    }

    func testSkipsConversationsOnCooldown() {
        let provider = makeProvider()
        // water_1 はクールダウン中（30 分前に再生、cooldown 60 分）
        let lastShown = ["water_1": now.addingTimeInterval(-1800)]
        XCTAssertEqual(provider.pick(context: context(allowed: [.water], lastShownAt: lastShown))?.id, "water_2")

        // 両方クールダウン中なら黙る
        let bothShown = ["water_1": now.addingTimeInterval(-1800), "water_2": now.addingTimeInterval(-60)]
        XCTAssertNil(provider.pick(context: context(allowed: [.water], lastShownAt: bothShown)))

        // クールダウンが明けていれば選ばれる
        let expired = ["water_1": now.addingTimeInterval(-3601)]
        XCTAssertEqual(provider.pick(context: context(allowed: [.water], lastShownAt: expired))?.id, "water_1")
    }

    func testAvoidsLastCategory() {
        let provider = makeProvider()
        XCTAssertEqual(provider.pick(context: context(allowed: [.water, .break], lastCategory: .water))?.id, "break_1")
        // allowed がそのカテゴリだけなら許可する
        XCTAssertEqual(provider.pick(context: context(allowed: [.water], lastCategory: .water))?.id, "water_1")
    }

    func testExcludesRecentlyShownIDs() {
        let provider = makeProvider()
        XCTAssertEqual(provider.pick(context: context(allowed: [.water], recent: ["water_1"]))?.id, "water_2")
        XCTAssertNil(provider.pick(context: context(allowed: [.water], recent: ["water_1", "water_2"])))
    }

    func testManualTriggerAlwaysAnswers() {
        let provider = makeProvider()
        let allShown = [
            "ambient_1": now.addingTimeInterval(-60),
            "pair_1": now.addingTimeInterval(-60),
        ]
        // scheduled ならクールダウンで黙る
        XCTAssertNil(provider.pick(context: context(allowed: [.ambient, .pair],
                                                    recent: ["ambient_1", "pair_1"],
                                                    lastShownAt: allShown)))
        // manual なら条件をゆるめて必ず返す
        let manual = provider.pick(context: context(allowed: [.ambient, .pair],
                                                    recent: ["ambient_1", "pair_1"],
                                                    lastCategory: .ambient,
                                                    lastShownAt: allShown,
                                                    trigger: .manual))
        XCTAssertEqual(manual?.id, "pair_1")   // 直前カテゴリ（ambient）は最後まで避ける
    }

    func testAsyncEntryPoint() async {
        let provider = makeProvider()
        let picked = await provider.nextConversation(context: context(allowed: [.pair]))
        XCTAssertEqual(picked?.id, "pair_1")
    }
}
