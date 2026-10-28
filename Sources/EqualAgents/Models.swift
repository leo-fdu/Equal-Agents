import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct Member: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = ""
    var runtime = "codex"
    var provider = "OpenAI"
    var model = ""
    var effort = ""
    var persona = ""
    var payload: [String: Any] { ["name": name, "runtime": runtime, "provider": provider, "model": model, "effort": effort, "persona": persona] }
}
struct TopicMaterial: Codable, Identifiable {
    var id: String { kind + ":" + title + ":" + text }
    var kind: String
    var title: String
    var text: String
    var payload: [String: Any] { ["kind": kind, "title": title, "text": text] }
}

struct ModelChoice: Codable, Identifiable, Hashable {
    let id: String
    let runtime: String
    let model: String
    let provider: String
    let name: String
    let levels: [String]
    var label: String { "\(name) · \(runtime == "codex" ? "Codex" : "pi / " + provider)" }
}
struct Turn: Codable, Identifiable {
    let id: String
    let phase: String
    let round: Int
    let memberID: String
    let status: String
    let text: String
    let error: String
    let attempts: Int
    let memberSnapshot: Member?
    var phaseLabel: String {
        switch phase { case "opening": return "Opening"; case "proposal": return "Proposals"; case "discussion": return "Discussion · Round \(round)"; case "final": return "Closing"; case "report": return "Meeting report"; default: return phase }
    }
}
struct Source: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let text: String
    let kind: String
    let ownerIDs: [String]
    let characters: Int
}
struct ReadReceipt: Codable {
    let memberID: String
    let sourceID: String
    let turnID: String
    let offset: Int
    let end: Int
}
struct Room: Codable, Identifiable {
    let id: String
    let deletedAt: String?
    let topic: String
    let materials: [TopicMaterial]?
    let host: Member
    let members: [Member]
    let rounds: Int
    let shared: Bool
    let status: String
    let notice: String
    let turns: [Turn]
    let sources: [Source]
    let reads: [ReadReceipt]
    let createdAt: String
    let updatedAt: String
    var isRunning: Bool { status == "running" || status == "pausing" }
    var title: String { String(topic.split(separator: "\n").first ?? "New discussion").prefix(70).description }
    var statusLabel: String { ["draft": "Draft", "running": "Running", "pausing": "Pausing", "paused": "Paused", "completed": "Completed"][status] ?? status }
    var finished: Int { turns.filter { ["completed", "skipped"].contains($0.status) }.count }
    var report: String { turns.first { $0.phase == "report" && $0.status == "completed" }?.text ?? "" }
    func member(_ id: String) -> Member { ([host] + members).first { $0.id == id } ?? host }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor final class AppModel: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selection: String?
    @Published var models: [ModelChoice] = []
    @Published var recentModels: [ModelChoice] = []
    @Published var catalogErrors: [String: String] = [:]
    @Published var loadingModels = false
    @Published var ready = false
    @Published var error = ""
    @Published var serviceError = ""
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<Any, Error>] = [:]
    private var stopping = false
    let dataURL: URL
    var selected: Room? { rooms.first { $0.id == selection } }

    init() {
        if let data = UserDefaults.standard.data(forKey: "recentModelChoices"), let saved = try? JSONDecoder().decode([ModelChoice].self, from: data) { recentModels = saved }
        if let override = ProcessInfo.processInfo.environment["EQUAL_AGENTS_DATA"] ?? Bundle.main.object(forInfoDictionaryKey: "EqualAgentsDataDirectory") as? String { dataURL = URL(fileURLWithPath: override) }
        else { dataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Equal Agents") }
        launch()
    }
    func launch() {
        guard process == nil else { return }
        do {
            try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
            let resources = Bundle.main.resourceURL!
            let env = ProcessInfo.processInfo.environment
            let engine = env["EQUAL_AGENTS_ENGINE"] ?? resources.appendingPathComponent("engine/server.mjs").path
            let node = env["EQUAL_AGENTS_NODE"] ?? resources.appendingPathComponent("node").path
            guard FileManager.default.isExecutableFile(atPath: node), FileManager.default.fileExists(atPath: engine) else { throw AppError.message("The bundled engine is missing. Please launch the built Equal Agents.app.") }
            let task = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            task.executableURL = URL(fileURLWithPath: node); task.arguments = [engine, dataURL.path]
            var environment = env
            environment["PATH"] = resources.path + ":/opt/homebrew/bin:/usr/local/bin:" + FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            task.environment = environment; task.standardInput = stdin; task.standardOutput = stdout; task.standardError = stderr
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                Task { @MainActor in self?.consume(data) }
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in if !text.contains("ExperimentalWarning") { self?.serviceError = String(text.suffix(2000)) } }
            }
            task.terminationHandler = { [weak self] _ in Task { @MainActor in self?.disconnected() } }
            input = stdin.fileHandleForWriting; process = task
            try task.run()
        } catch { process = nil; self.error = error.localizedDescription }
    }
    private func disconnected() {
        ready = false; process = nil
        for continuation in pending.values { continuation.resume(throwing: AppError.message("The meeting engine stopped")) }; pending.removeAll()
        if !stopping { error = "The engine stopped. Restart the app to recover saved meetings.\n" + serviceError }
    }
    private func consume(_ data: Data) {
        buffer.append(data)
        while let i = buffer.firstIndex(of: 10) {
            let line = buffer[..<i]; buffer.removeSubrange(...i)
            do {
                guard let value = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if value["type"] as? String == "ready" {
                    ready = true
                    Task { await refresh(); await loadModels() }
                } else if let raw = value["room"] as? [String: Any] {
                    let room: Room = try decode(raw)
                    if let index = rooms.firstIndex(where: { $0.id == room.id }) { rooms[index] = room } else { rooms.insert(room, at: 0) }
                } else if let id = value["id"] as? String, let continuation = pending.removeValue(forKey: id) {
                    if let message = value["error"] as? String { continuation.resume(throwing: AppError.message(message)) }
                    else { continuation.resume(returning: value["result"] ?? NSNull()) }
                }
            } catch { self.error = "Could not read meeting data: " + error.localizedDescription }
        }
    }
    func decode<T: Decodable>(_ value: Any) throws -> T { try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) }
    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> Any {
        guard ready, let input else { throw AppError.message("The meeting engine is not ready") }
        let id = UUID().uuidString
        var data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params]); data.append(10)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try input.write(contentsOf: data) }
            catch { pending.removeValue(forKey: id); continuation.resume(throwing: error) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(90))
                if let c = self?.pending.removeValue(forKey: id) { c.resume(throwing: AppError.message("The operation timed out. Check your framework installation and sign-in status.")) }
            }
        }
    }
    func refresh() async {
        do { rooms = try decode(try await request("list", ["includeDeleted": true])); if selection == nil { selection = rooms.first(where: { $0.deletedAt == nil })?.id } }
        catch { self.error = error.localizedDescription }
    }
    func loadModels() async {
        guard !loadingModels else { return }; loadingModels = true; catalogErrors = [:]
        async let codex: Void = loadCatalog("codex")
        async let pi: Void = loadCatalog("pi")
        _ = await (codex, pi); loadingModels = false
    }
    func rememberModel(_ choice: ModelChoice) {
        recentModels.removeAll { $0.id == choice.id }
        recentModels.insert(choice, at: 0)
        recentModels = Array(recentModels.prefix(20))
        if let data = try? JSONEncoder().encode(recentModels) { UserDefaults.standard.set(data, forKey: "recentModelChoices") }
    }
    private func loadCatalog(_ runtime: String) async {
        do {
            let choices: [ModelChoice] = try decode(try await request("catalog", ["runtime": runtime]))
            models.removeAll { $0.runtime == runtime }; models += choices
            models.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        } catch { catalogErrors[runtime] = error.localizedDescription }
    }
    func control(_ method: String, room: Room, turnID: String? = nil) async {
        do { var params = ["id": room.id]; if let turnID { params["turnID"] = turnID }; _ = try await request(method, params) }
        catch { self.error = error.localizedDescription }
    }
    func create(topic: String, materials: [TopicMaterial] = [], host: Member, members: [Member], rounds: Int, shared: Bool, seconds: Int?, length: Int?) async -> Bool {
        do {
            let room: Room = try decode(try await request("create", ["topic": topic, "materials": materials.map(\.payload), "host": host.payload, "members": members.map(\.payload), "rounds": rounds, "shared": shared, "turnSeconds": seconds.map { $0 as Any } ?? NSNull(), "responseLength": length.map { $0 as Any } ?? NSNull()]))
            selection = room.id; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func pickTopicFiles() -> [TopicMaterial] {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf, .plainText, .json, .html]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        do {
            return try panel.urls.map { url in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw AppError.message("Files must be 20 MB or smaller") }
                let text: String
                if url.pathExtension.lowercased() == "pdf" {
                    guard let doc = PDFDocument(url: url), let content = doc.string, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("This PDF has no extractable text. OCR is not included.") }
                    text = content
                } else { text = try String(contentsOf: url, encoding: .utf8) }
                guard text.count <= 100_000 else { throw AppError.message("Topic files must total at most 100,000 characters. Add larger files in shared sources after creating the meeting.") }
                return TopicMaterial(kind: "file", title: url.lastPathComponent, text: text)
            }
        } catch { self.error = error.localizedDescription; return [] }
    }
    func attach(_ room: Room) async {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf, .plainText, .json, .html]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                guard (attrs[.size] as? NSNumber)?.intValue ?? 0 <= 20_000_000 else { throw AppError.message("Attachments must be 20 MB or smaller") }
                let text: String
                if url.pathExtension.lowercased() == "pdf" {
                    guard let doc = PDFDocument(url: url) else { throw AppError.message("Could not open the PDF") }
                    text = (0..<doc.pageCount).map { "[Page \($0 + 1)]\n" + (doc.page(at: $0)?.string ?? "") }.joined(separator: "\n\n")
                    guard text.count > doc.pageCount * 12 else { throw AppError.message("The PDF has no extractable text. OCR is not included in this version.") }
                } else { text = try String(contentsOf: url, encoding: .utf8) }
                _ = try await request("attach", ["id": room.id, "title": url.lastPathComponent, "text": text])
            }
        } catch { self.error = error.localizedDescription }
    }
    func export(_ room: Room, reportOnly: Bool = false) async {
        do {
            let text = reportOnly ? room.report : (try await request("export", ["id": room.id]) as? String ?? "")
            let panel = NSSavePanel(); panel.nameFieldStringValue = reportOnly ? "Equal Agents Report.md" : "Equal Agents Transcript.md"; panel.allowedContentTypes = [.plainText]
            if panel.runModal() == .OK, let url = panel.url { try text.write(to: url, atomically: true, encoding: .utf8) }
        } catch { self.error = error.localizedDescription }
    }
    func shutdown() async {
        stopping = true
        if let input { try? input.write(contentsOf: Data("{\"method\":\"shutdown\"}\n".utf8)) }
        for _ in 0..<40 { if process?.isRunning != true { return }; try? await Task.sleep(for: .milliseconds(100)) }
        process?.terminate()
    }
}
