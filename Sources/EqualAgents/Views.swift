import SwiftUI

private let accent = Color(red: 0.12, green: 0.52, blue: 0.49)

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @State private var creating = false
    @State private var search = ""
    @State private var settings = false
    @State private var showDeleted = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "equal.circle.fill").font(.system(size: 30)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) { Text("Equal Agents").font(.headline); Text("A meeting of minds").font(.caption).foregroundStyle(.secondary) }
                }.padding(.top, 14)
                Button { creating = true } label: { Label("New discussion", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(accent).disabled(!app.ready)
                TextField("Search discussions", text: $search).textFieldStyle(.roundedBorder)
                if showDeleted { Text("Recently Deleted").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                List(selection: $app.selection) {
                    ForEach(app.rooms.filter { ($0.deletedAt != nil) == showDeleted && (search.isEmpty || $0.topic.localizedCaseInsensitiveContains(search)) }) { room in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(room.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            HStack(spacing: 5) { Circle().fill(room.isRunning ? accent : .secondary.opacity(0.4)).frame(width: 5, height: 5); Text(room.statusLabel); Spacer(); Text("\(room.members.count) participants") }.font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 7).tag(room.id)
                        .contextMenu {
                            if room.deletedAt != nil {
                                Button("Restore discussion") { Task { await app.control("restore", room: room) } }
                            } else {
                                Button("Delete discussion", role: .destructive) { Task { await app.control("delete", room: room) } }
                            }
                        }
                    }
                }.listStyle(.sidebar).padding(.horizontal, -12)
                Spacer(minLength: 0)
                Button { showDeleted.toggle(); app.selection = nil } label: {
                    Label(showDeleted ? "All discussions" : "Recently Deleted", systemImage: showDeleted ? "bubble.left.and.bubble.right" : "trash")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button { settings = true } label: { Label("Frameworks & models", systemImage: "slider.horizontal.3").font(.callout) }.buttonStyle(.plain).foregroundStyle(.secondary)
                HStack(spacing: 5) { Circle().fill(app.ready ? accent : .orange).frame(width: 5, height: 5); Text(app.ready ? "Local engine connected" : "Connecting to local engine…") }.font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.bottom, 16)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            if let room = app.selected, room.deletedAt != nil {
                VStack(spacing: 18) {
                    Image(systemName: "trash").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Discussion deleted").font(.title2.bold())
                    Text("Your transcript and shared sources are preserved. You can restore this discussion from Recently Deleted.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
                    Button("Restore discussion") { Task { await app.control("restore", room: room); showDeleted = false } }.disabled(room.isRunning)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else if let room = app.selected {
                GeometryReader { viewport in
                    RoomView(room: room).id(room.id)
                        .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
                        .clipped()
                }
            }
            else {
                VStack(spacing: 20) {
                    Image(systemName: "equal.circle").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(accent)
                    Text("Different minds. Equal voices.").font(.system(size: 29, weight: .semibold))
                    Text("One host. Independent participants.\nPropose, discuss, and bring the ideas together.").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
                    Button("Start a discussion") { creating = true }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large).disabled(!app.ready)
                    Text("Codex + pi · Native macOS · Optional shared sources").font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.tint(accent)
        .onChange(of: creating) { _, value in if value { showDeleted = false } }
        .sheet(isPresented: $creating) { NewMeetingView() }
        .sheet(isPresented: $settings) { ConnectionView() }
        .alert("Equal Agents", isPresented: Binding(get: { !app.error.isEmpty }, set: { if !$0 { app.error = "" } })) { Button("OK") { app.error = "" } } message: { Text(app.error) }
        .toolbar {
            ToolbarItem { if let room = app.selected, room.deletedAt == nil {
                Button { Task { await app.control("delete", room: room) } } label: { Image(systemName: "trash") }.help("Delete discussion")
            } }
            ToolbarItem { Button { creating = true; showDeleted = false } label: { Image(systemName: "square.and.pencil") }.help("New discussion").disabled(!app.ready) }
        }
    }
}

struct NewMeetingView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var topic = ""
    @State private var materials: [TopicMaterial] = []
    @State private var link = ""
    @State private var materialError = ""
    @State private var host = Member(name: "Host")
    @State private var members = [Member(name: "Participant A"), Member(name: "Participant B")]
    @State private var rounds = 2
    @State private var shared = true
    @State private var seconds = 300
    @State private var limitTime = false
    @State private var limitLength = false
    @State private var length = 600
    @State private var saving = false
    var valid: Bool { !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !host.model.isEmpty && members.allSatisfy { !$0.model.isEmpty } }
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("New discussion").font(.title2.bold()); Text("Think independently. Then exchange ideas.").foregroundStyle(.secondary) }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Discussion topic").font(.headline)
                        MultilineInput(text: $topic, label: "Discussion topic").frame(height: 100).padding(8).background(.background).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        Text("Describe the question, goals, and constraints. Participants speak in the language of your topic.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button { addMaterials(app.pickTopicFiles()) } label: { Label("Add files", systemImage: "paperclip") }
                            TextField("https://…", text: $link).textFieldStyle(.roundedBorder)
                            Button("Add link") {
                                let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { materialError = "Enter a valid HTTP or HTTPS link."; return }
                                addMaterials([TopicMaterial(kind: "link", title: value, text: value)]); link = ""
                            }.disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        ForEach(materials) { material in
                            HStack {
                                Image(systemName: material.kind == "file" ? "doc.text" : "link")
                                Text(material.title).lineLimit(1); Spacer()
                                Button { materials.removeAll { $0.id == material.id } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).help("Remove material")
                            }.font(.caption)
                        }
                        Text("PDF and text files · Initial materials are visible to everyone, even with shared sources off. Links are references for participants to open.").font(.caption).foregroundStyle(.secondary)
                        if !materialError.isEmpty { Text(materialError).font(.caption).foregroundStyle(.orange) }

                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Host", systemImage: "mic").font(.headline)
                        Text("Opens the meeting and writes the final report. Does not join proposals or discussion.").font(.caption).foregroundStyle(.secondary)
                        MemberEditor(member: $host, isHost: true)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Label("Participants", systemImage: "person.2").font(.headline); Spacer(); Button { members.append(Member(name: "Participant \(members.count + 1)")) } label: { Label("Add", systemImage: "plus") }.disabled(members.count >= 8) }
                        ForEach($members) { $member in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Text("Seat \((members.firstIndex(where: { $0.id == member.id }) ?? 0) + 1)").font(.caption).foregroundStyle(.secondary); Spacer(); Button { members.removeAll { $0.id == member.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).disabled(members.count <= 2) }
                                MemberEditor(member: $member, isHost: false)
                            }.padding(14).background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                        }
                        Text("Discussion and closing statements follow seat order. Role prompts are optional; multiple participants may use the same model.").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Meeting rules").font(.headline)
                        Stepper("Discussion stage rounds: \(rounds)", value: $rounds, in: 1...12)
                        Text("Stage 2 only. Each round gives every participant one turn. Proposals and closing statements happen once each.").font(.caption).foregroundStyle(.secondary)
                        Toggle("Enable shared sources", isOn: $shared)
                        Text(shared ? "Search results are archived automatically. New peer sources become visible after proposals. You can attach files before starting." : "No shared library. Participants can still search and cite original links in their statements.").font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Time & response length") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Set a time limit per turn", isOn: $limitTime)
                                if limitTime { Picker("Time per turn", selection: $seconds) { Text("3 minutes").tag(180); Text("5 minutes").tag(300); Text("10 minutes").tag(600); Text("20 minutes").tag(1200) } } else { Text("No time limit").font(.caption).foregroundStyle(.secondary) }
                                Toggle("Suggest a response length", isOn: $limitLength)
                                if limitLength { Picker("Suggested length", selection: $length) { Text("Brief · 300 characters").tag(300); Text("Balanced · 600 characters").tag(600); Text("Detailed · 1,200 characters").tag(1200) } } else { Text("No length limit").font(.caption).foregroundStyle(.secondary) }
                                Text("Length is a suggestion, never a truncation. Model context limits and network errors can still pause a meeting.").font(.caption).foregroundStyle(.secondary)
                            }.padding(.top, 8)
                        }
                    }
                }.padding(24)
            }
            Divider()
            HStack { Text("\(2 + members.count * (rounds + 2)) planned statements").font(.caption).foregroundStyle(.secondary); Spacer(); if saving { ProgressView().controlSize(.small) }; Button("Create meeting") {
                saving = true
                Task { if await app.create(topic: topic, materials: materials, host: host, members: members, rounds: rounds, shared: shared, seconds: limitTime ? seconds : nil, length: limitLength ? length : nil) { dismiss() }; saving = false }
            }.buttonStyle(.borderedProminent).disabled(!valid || saving).keyboardShortcut(.defaultAction) }.padding(20)
        }.frame(width: 740, height: 780)
    }
    func addMaterials(_ additions: [TopicMaterial]) {
        let unique = additions.filter { item in !materials.contains { $0.id == item.id } }
        let combined = materials + unique
        guard combined.count <= 20, combined.reduce(0, { $0 + $1.text.utf16.count }) <= 100_000 else { materialError = "Use up to 20 items and 100,000 characters in total."; return }
        materials = combined; materialError = ""
    }
}

struct MemberEditor: View {
    @EnvironmentObject var app: AppModel
    @Binding var member: Member
    let isHost: Bool
    @State private var levels: [String] = []
    @State private var levelError = ""
    @State private var choosingModel = false
    @State private var customProvider = false
    @State private var savedScopes: [String: Member] = [:]
    @State private var lastProviders: [String: String] = [:]
    var providers: [String] { Array(Set(app.models.filter { $0.runtime == "pi" }.map(\.provider))).sorted() }
    var modelIDs: [String] { Array(Set(app.models.filter { $0.runtime == member.runtime && (member.runtime == "codex" || $0.provider == member.provider) }.map(\.model))).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(isHost ? "Host name" : "Display name", text: $member.name).textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("Framework").font(.caption).foregroundStyle(.secondary)
                ForEach(["codex", "pi"], id: \.self) { value in
                    Button {
                        guard value != member.runtime else { return }
                        let provider = value == "codex" ? "OpenAI" : lastProviders["pi"] ?? app.recentModels.first(where: { $0.runtime == "pi" })?.provider ?? ""
                        switchScope(runtime: value, provider: provider)
                        customProvider = false
                    } label: {
                        Text(value == "codex" ? "Codex" : "pi").font(.callout.weight(.medium)).frame(width: 78).padding(.vertical, 7)
                            .foregroundStyle(member.runtime == value ? Color.white : Color.primary)
                            .background(member.runtime == value ? accent : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("framework-\(member.id)-\(value)")
                }
            }
            if member.runtime == "pi" {
                HStack {
                    Text("Provider").font(.caption).foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
                    Menu {
                        ForEach(providers, id: \.self) { provider in
                            Button(provider) { switchScope(runtime: "pi", provider: provider); customProvider = false }
                        }
                        Divider()
                        Button("Other provider…") { switchScope(runtime: "pi", provider: ""); customProvider = true }
                    } label: {
                        HStack { Text(member.provider.isEmpty ? "Choose a provider" : member.provider); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption2) }
                            .padding(.horizontal, 10).padding(.vertical, 8).background(.quinary, in: RoundedRectangle(cornerRadius: 7))
                    }.menuStyle(.borderlessButton)
                }
                if customProvider || (!member.provider.isEmpty && !providers.contains(member.provider)) {
                    TextField("Exact provider ID", text: Binding(get: { member.provider }, set: { value in
                        var updated = member; updated.provider = value; updated.model = ""; updated.effort = ""; member = updated
                    })).textFieldStyle(.roundedBorder)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Model").font(.caption).foregroundStyle(.secondary)
                Button { choosingModel = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.model.isEmpty ? "Choose or enter a model…" : selectedName).font(.callout.weight(.medium)).lineLimit(1)
                            if !member.model.isEmpty && selectedName != member.model { Text(member.model).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        if app.loadingModels { ProgressView().controlSize(.mini) }
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .background(.background, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
                }.buttonStyle(.plain).disabled(member.runtime == "pi" && member.provider.isEmpty)
                .popover(isPresented: $choosingModel, arrowEdge: .bottom) {
                    ModelPickerPanel(runtime: member.runtime, provider: member.provider, currentID: member.model) { choice in
                        var updated = member; updated.model = choice.model; updated.effort = ""; member = updated
                        savedScopes[member.runtime + ":" + member.provider] = updated
                    }.environmentObject(app)
                }
                if member.runtime == "pi" && member.provider.isEmpty { Text("Choose a provider first.").font(.caption2).foregroundStyle(.secondary) }
            }
            Picker("Reasoning effort", selection: $member.effort) { Text("Model default").tag(""); ForEach(levels, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 330)
            if !levelError.isEmpty { Text(levelError).font(.caption).foregroundStyle(.orange) }
            if !isHost {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Personality / role prompt (optional)").font(.caption).foregroundStyle(.secondary)
                    MultilineInput(text: $member.persona, label: "Personality / role prompt").frame(height: 130).padding(8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    Text("Private to this participant · Not shared with other agents or the host.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.task(id: member.runtime + ":" + member.provider + ":" + member.model) {
            levelError = ""; levels = []
            guard !member.model.isEmpty else { return }
            if member.runtime == "codex" { levels = app.models.first { $0.model == member.model && $0.runtime == "codex" }?.levels ?? [] }
            else if modelIDs.contains(member.model) {
                do {
                    try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation()
                    let result: [String] = try app.decode(try await app.request("levels", member.payload))
                    try Task.checkCancellation(); levels = result
                } catch is CancellationError {} catch { levelError = "Could not read reasoning levels. Model default is available." }
            }
        }
    }
    var selectedName: String { app.models.first { $0.runtime == member.runtime && $0.provider == member.provider && $0.model == member.model }?.name ?? member.model }
    func switchScope(runtime: String, provider: String) {
        savedScopes[member.runtime + ":" + member.provider] = member
        lastProviders[member.runtime] = member.provider
        var updated = member
        updated.runtime = runtime; updated.provider = provider; updated.model = ""; updated.effort = ""
        if let previous = savedScopes[runtime + ":" + provider] { updated.model = previous.model; updated.effort = previous.effort }
        else if let recent = app.recentModels.first(where: { $0.runtime == runtime && $0.provider == provider }) { updated.model = recent.model }
        member = updated; levels = []
    }

}

struct RoomView: View {
    @EnvironmentObject var app: AppModel
    let room: Room
    @State private var tab = "discussion"
    @State private var selectedSource: Source?
    @State private var follow = false
    @State private var showPeople = false
    @State private var editingMember: Member?
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) { Text(room.title).font(.title2.bold()).lineLimit(2); Text("\(room.members.count) participants · \(room.rounds) discussion rounds · \(room.shared ? "Shared sources on" : "Shared sources off")").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if room.isRunning { Button { Task { await app.control("pause", room: room) } } label: { Label("Pause", systemImage: "pause.fill") }.disabled(room.status == "pausing") }
                    else if room.status != "completed" { Button { Task { await app.control("start", room: room) } } label: { Label(room.status == "draft" ? "Start meeting" : "Resume / retry", systemImage: "play.fill") }.buttonStyle(.borderedProminent).tint(accent) }
                    Menu { Button("Export full transcript") { Task { await app.export(room) } }; Button("Export final report") { Task { await app.export(room, reportOnly: true) } }.disabled(room.report.isEmpty) } label: { Image(systemName: "square.and.arrow.up") }.menuStyle(.borderlessButton).fixedSize()
                }
                HStack(spacing: 8) {
                    stage("Opening", phases: ["opening"]); stage("Proposals", phases: ["proposal"]); stage("Discussion", phases: ["discussion"]); stage("Closing", phases: ["final"]); stage("Report", phases: ["report"])
                    Spacer(); Text("\(room.finished) / \(room.turns.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack {
                    Picker("View", selection: $tab) { Text("Discussion").tag("discussion"); Text("Sources \(room.sources.count)").tag("sources"); Text("Report").tag("report") }.pickerStyle(.segmented).labelsHidden().frame(width: 330)
                    Spacer(); Button { showPeople.toggle() } label: { Label("Participants", systemImage: "person.2") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.fixedSize(horizontal: false, vertical: true).padding(24)
            Divider()
            if !room.notice.isEmpty { HStack { Image(systemName: room.status == "completed" ? "checkmark.circle" : "info.circle"); Text(room.notice).font(.caption); Spacer() }.foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10).background(accent.opacity(0.05)) }
            Group {
                if tab == "discussion" { discussion }
                else if tab == "sources" { sourceList }
                else { report }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $selectedSource) { source in
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(source.title).font(.title3.bold()); Spacer(); Button("Done") { selectedSource = nil } }
                if let url = URL(string: source.url), ["http", "https"].contains(url.scheme) { Link(source.url, destination: url).font(.caption).lineLimit(2) }
                Text("\(source.id) · \(source.characters) characters · \(room.reads.filter { $0.sourceID == source.id }.count) passage deliveries").font(.caption).foregroundStyle(.secondary)
                Text("Read receipts track delivered passages, not proof of full reading or understanding.").font(.caption).foregroundStyle(.secondary)
                Divider(); ScrollView { Text(source.text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(24).frame(width: 700, height: 620)
        }
        .sheet(isPresented: $showPeople) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Meeting members").font(.title2.bold()); Spacer(); Button("Done") { showPeople = false } }
                ScrollView { VStack(alignment: .leading, spacing: 20) {
                    Text(room.topic).textSelection(.enabled)
                    ForEach(room.materials ?? []) { material in
                        DisclosureGroup(material.title) { Text(material.text).font(.callout).textSelection(.enabled) }
                    }
                    Divider()
                    ForEach([room.host] + room.members) { m in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(m.name + (m.id == room.host.id ? " · Host" : "")).font(.headline); Spacer(); if !room.isRunning && room.status != "completed" { Button("Change model") { editingMember = m } } }
                            Text("\(m.runtime) / \(m.provider) / \(m.model)").font(.caption).foregroundStyle(.secondary)
                            if !m.persona.isEmpty { Text(m.persona).font(.callout).textSelection(.enabled) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(24).frame(width: 600, height: 550)
                .sheet(item: $editingMember) { member in EditMemberView(room: room, initial: member) }
        }
    }
    func stage(_ name: String, phases: [String]) -> some View {
        let turns = room.turns.filter { phases.contains($0.phase) }
        let complete = turns.allSatisfy { ["completed", "skipped"].contains($0.status) }
        let active = turns.contains { $0.status == "running" }
        return HStack(spacing: 5) { Image(systemName: complete ? "checkmark.circle.fill" : active ? "circle.inset.filled" : "circle"); Text(name) }.font(.caption).foregroundStyle(complete || active ? accent : .secondary).padding(.vertical, 7).padding(.horizontal, 9).background(active ? accent.opacity(0.1) : .clear, in: Capsule())
    }
    var discussion: some View {
        VStack(spacing: 0) {
            if room.status == "draft" { ContentUnavailableView { Label("Ready when you are", systemImage: "bubble.left.and.bubble.right") } description: { Text(room.shared ? "Add attachments in Sources, or start the meeting now." : "Start the meeting to hear the host introduce your topic.") } }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Color.clear.frame(height: 1).id("top")
                            ForEach(room.turns.filter { $0.status != "pending" }) { turn in TurnCard(turn: turn, member: turn.memberSnapshot ?? room.member(turn.memberID), room: room) }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(24).frame(maxWidth: 960).frame(maxWidth: .infinity)
                    }.background(ScrollIntentObserver { follow = false })
                    .onChange(of: follow) { _, enabled in if enabled { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: room.turns.map { $0.text.count + $0.status.count }) { _, _ in if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onAppear { proxy.scrollTo("top", anchor: .top) }
                }
                HStack { Text(room.statusLabel).font(.caption).foregroundStyle(.secondary); Spacer(); Button { follow.toggle() } label: { Label(follow ? "Following latest · Pause" : "Jump to latest", systemImage: follow ? "pause.circle" : "arrow.down.circle") }.buttonStyle(.plain).font(.caption) }.padding(.horizontal, 24).padding(.vertical, 10)
            }
        }
    }
    var sourceList: some View {
        VStack(spacing: 0) {
            if !room.shared { ContentUnavailableView("Shared sources are off", systemImage: "folder", description: Text("References are kept within participant statements for this meeting.")) }
            else {
                HStack { Text("Automatically archived · Peer sources unlock after proposals").font(.caption).foregroundStyle(.secondary); Spacer(); Button { Task { await app.attach(room) } } label: { Label("Add files", systemImage: "plus") }.disabled(room.status != "draft") }.padding(20)
                if room.sources.isEmpty { ContentUnavailableView("No sources yet", systemImage: "doc.text.magnifyingglass", description: Text("Add PDFs or text files, or wait for participants to search.")) }
                else {
                    List(room.sources) { source in
                        Button { selectedSource = source } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: source.kind == "attachment" ? "doc.text" : "link").foregroundStyle(accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 5) { Text(source.title).font(.headline); Text(source.url.isEmpty ? "User attachment" : source.url).font(.caption).foregroundStyle(.secondary).lineLimit(1); Text("\(source.id) · \(source.kind == "search_result" ? "Search snippet" : "Content") · \(source.characters) characters").font(.caption2).foregroundStyle(.tertiary) }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.listStyle(.inset)
                }
            }
        }
    }
    var report: some View {
        Group {
            if room.report.isEmpty { ContentUnavailableView("Your report appears after the discussion", systemImage: "doc.richtext", description: Text("The host will summarize positions, consensus, and disagreement from the full transcript.")) }
            else { ScrollView { MarkdownText(text: room.report).padding(32).frame(maxWidth: 900).frame(maxWidth: .infinity, alignment: .center) } }
        }
    }
}

struct TurnCard: View {
    @EnvironmentObject var app: AppModel
    let turn: Turn
    let member: Member
    let room: Room
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack { RoundedRectangle(cornerRadius: 10).fill(accent.opacity(member.id == room.host.id ? 0.18 : 0.08)); Text(String(member.name.prefix(1))).font(.headline).foregroundStyle(accent) }.frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) { Text(member.name).font(.headline); Text("\(turn.id) · \(turn.phaseLabel) · \(member.model)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if turn.status == "running" { ProgressView().controlSize(.small); Text("Thinking / speaking").font(.caption).foregroundStyle(.secondary) }
                if turn.status == "skipped" { Text("Skipped").font(.caption).foregroundStyle(.orange) }
            }
            if !turn.text.isEmpty { MarkdownText(text: turn.text) }
            else if turn.status == "running" { Text("Waiting for the model…").font(.callout).foregroundStyle(.tertiary) }
            if !turn.error.isEmpty {
                Text(turn.error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                if !room.isRunning && ["failed", "interrupted"].contains(turn.status) && !["opening", "report"].contains(turn.phase) {
                    Button("Skip this statement") { Task { await app.control("skip", room: room, turnID: turn.id) } }.font(.caption)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

struct MarkdownText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                if paragraph.hasPrefix("#") {
                    Text(paragraph.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)).font(paragraph.hasPrefix("###") ? .headline : .title3.bold()).textSelection(.enabled)
                } else if paragraph.hasPrefix("```") {
                    Text(paragraph).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quinary, in: RoundedRectangle(cornerRadius: 7))
                } else {
                    Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph)).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditMemberView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    let room: Room
    @State var member: Member
    @State private var saving = false
    init(room: Room, initial: Member) { self.room = room; _member = State(initialValue: initial) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Change model for future turns").font(.title2.bold())
            Text("Completed statements keep their original model details. After the meeting starts, changes affect only the framework, model, and reasoning effort.").font(.caption).foregroundStyle(.secondary)
            MemberEditor(member: $member, isHost: true)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save") {
                saving = true
                Task { do { _ = try await app.request("updateMember", ["id": room.id, "memberID": member.id, "settings": member.payload]); dismiss() } catch { app.error = error.localizedDescription }; saving = false }
            }.buttonStyle(.borderedProminent).disabled(saving || member.model.isEmpty) }
        }.padding(24).frame(width: 650)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Frameworks & models").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Uses the accounts and providers configured in your local Codex and pi installations. Equal Agents does not copy credentials.").foregroundStyle(.secondary)
            ForEach(["codex", "pi"], id: \.self) { runtime in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(runtime == "codex" ? "Codex" : "pi").font(.headline); Spacer(); Text("\(app.models.filter { $0.runtime == runtime }.count) models").foregroundStyle(.secondary) }
                    if let error = app.catalogErrors[runtime] { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    else { Text(app.loadingModels ? "Loading…" : "Catalog loaded. Model access depends on provider credentials and available quota.").font(.caption).foregroundStyle(.secondary) }
                }.padding(16).background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            }
            Button { Task { await app.loadModels() } } label: { Label("Refresh model catalogs", systemImage: "arrow.clockwise") }.disabled(app.loadingModels)
            Divider()
            Text("Install and sign in to Codex or pi first. For custom installations, set EQUAL_AGENTS_CODEX or EQUAL_AGENTS_PI to the executable path.").font(.caption).foregroundStyle(.secondary)
            Text("Meetings are stored locally. Inference and search still contact their respective services.").font(.caption).foregroundStyle(.secondary)
            Button("Show meeting data in Finder") { NSWorkspace.shared.open(app.dataURL) }
            Spacer()
        }.padding(28).frame(width: 580, height: 540)
    }
}
