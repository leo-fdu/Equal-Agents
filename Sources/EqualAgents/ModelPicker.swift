import SwiftUI

enum ModelSearch {
    static func words(_ value: String) -> [String] {
        value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
    static func matches(_ model: ModelChoice, query: String) -> Bool {
        let tokens = words(query)
        let text = words(model.name + " " + model.model).joined(separator: " ")
        let compact = words(model.name + " " + model.model).joined()
        return tokens.allSatisfy { text.contains($0) || compact.contains($0) }
    }
    static func results(_ models: [ModelChoice], runtime: String, provider: String, query: String) -> [ModelChoice] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func score(_ m: ModelChoice) -> Int {
            if m.model.lowercased() == query.lowercased() { return 0 }
            if m.model.lowercased().hasPrefix(query.lowercased()) { return 1 }
            if m.name.lowercased().hasPrefix(query.lowercased()) { return 2 }
            return 3
        }
        return models.filter { $0.runtime == runtime && $0.provider == provider && matches($0, query: query) }.sorted {
            score($0) != score($1) ? score($0) < score($1) : $0.model.localizedStandardCompare($1.model) == .orderedAscending
        }
    }
    static func recent(_ models: [ModelChoice], runtime: String, provider: String) -> [ModelChoice] {
        var seen = Set<String>()
        return Array(models.filter { $0.runtime == runtime && $0.provider == provider && seen.insert($0.id).inserted }.prefix(4))
    }
}

struct ModelPickerPanel: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    let runtime: String
    let provider: String
    let currentID: String
    let choose: (ModelChoice) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searching: Bool
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [ModelChoice] { ModelSearch.results(app.models, runtime: runtime, provider: provider, query: query) }
    private var recent: [ModelChoice] { trimmed.isEmpty ? ModelSearch.recent(app.recentModels, runtime: runtime, provider: provider) : [] }
    private var candidates: [ModelChoice] { recent + matches.filter { m in !recent.contains { $0.id == m.id } } }
    private var custom: ModelChoice? {
        guard !trimmed.isEmpty, !matches.contains(where: { $0.model == trimmed }) else { return nil }
        return ModelChoice(id: "\(runtime):\(provider):\(trimmed)", runtime: runtime, model: trimmed, provider: provider, name: trimmed, levels: [])
    }
    private var items: [ModelChoice] { candidates + (custom.map { [$0] } ?? []) }
    private func select(_ model: ModelChoice) { app.rememberModel(model); choose(model); dismiss() }
    private func move(_ delta: Int) { highlighted = min(max(0, highlighted + delta), max(0, items.count - 1)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose a model").font(.headline)
                    Text(runtime == "codex" ? "Codex · OpenAI" : "pi · \(provider)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if app.loadingModels { ProgressView().controlSize(.small) }
                Button { Task { await app.loadModels() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh models").disabled(app.loadingModels)
            }.padding(16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search models or enter an exact ID", text: $query).textFieldStyle(.plain).focused($searching)
                    .onSubmit { if items.indices.contains(highlighted) { select(items[highlighted]) } }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear search") }
            }.padding(11).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12).padding(.bottom, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(app.loadingModels ? "Loading models…" : "No models in this catalog").font(.callout.weight(.medium))
                                Text("You can still enter an exact model ID above.").font(.caption).foregroundStyle(.secondary)
                            }.padding(16)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, model in
                            if index == 0 && !recent.isEmpty { section("RECENTLY USED") }
                            if index == recent.count && index < candidates.count { section(trimmed.isEmpty ? "ALL MODELS" : "MATCHES · \(matches.count)") }
                            if index == candidates.count { section("CUSTOM MODEL") }
                            Button { select(model) } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: index >= candidates.count ? "keyboard" : index < recent.count ? "clock" : "sparkles").foregroundStyle(.secondary).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(index >= candidates.count ? "Use \"\(model.model)\"" : model.name).lineLimit(1).font(.callout.weight(.medium))
                                        if index >= candidates.count { Text("Custom ID · checked when the meeting starts").font(.caption).foregroundStyle(.secondary) }
                                        else if model.name != model.model { Text(model.model).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    Spacer()
                                    if model.model == currentID { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    .background(highlighted == index ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).id(index)
                        }
                    }.padding(8)
                }.frame(height: 310)
                .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
                .onChange(of: query) { _, _ in highlighted = 0; proxy.scrollTo(0) }
            }
            Divider()
            HStack {
                Text("↑ ↓ Navigate   ↵ Select   esc Close").font(.caption2).foregroundStyle(.secondary)
                Spacer(); Text("\(matches.count) models").font(.caption2).foregroundStyle(.secondary)
            }.padding(12)
            if let message = app.catalogErrors[runtime] {
                Text("Catalog unavailable: \(message)").font(.caption).foregroundStyle(.orange).lineLimit(3).padding(.horizontal, 12).padding(.bottom, 12)
            }
        }.frame(width: 460).onAppear { searching = true }
    }
    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
    }
}
