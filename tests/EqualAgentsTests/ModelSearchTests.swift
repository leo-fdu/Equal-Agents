import XCTest
@testable import EqualAgents
final class ModelSearchTests: XCTestCase {
    func model(_ id: String, provider: String = "OpenAI", runtime: String = "codex") -> ModelChoice {
        ModelChoice(id: "\(runtime):\(provider):\(id)", runtime: runtime, model: id, provider: provider, name: id, levels: [])
    }
    func testScopePreventsCrossProviderMatches() {
        let models = [model("gpt-6"), model("gpt-6", provider: "other", runtime: "pi")]
        XCTAssertEqual(ModelSearch.results(models, runtime: "codex", provider: "OpenAI", query: "gpt").count, 1)
    }
    func testCompactSearchAndRanking() {
        let models = [model("gpt-6-mini"), model("gpt-6"), model("gpt-5")]
        XCTAssertEqual(ModelSearch.results(models, runtime: "codex", provider: "OpenAI", query: "gpt6").map(\.model), ["gpt-6", "gpt-6-mini"])
        XCTAssertEqual(ModelSearch.results(models, runtime: "codex", provider: "OpenAI", query: "gpt-6").first?.model, "gpt-6")
        XCTAssertEqual(ModelSearch.results(models, runtime: "codex", provider: "OpenAI", query: "6 mini").map(\.model), ["gpt-6-mini"])
    }
    func testRecentOrderDeduplicationAndScope() {
        let models = [model("custom"), model("custom"), model("other", provider: "p", runtime: "pi"), model("gpt-6")]
        XCTAssertEqual(ModelSearch.recent(models, runtime: "codex", provider: "OpenAI").map(\.model), ["custom", "gpt-6"])
    }
}
