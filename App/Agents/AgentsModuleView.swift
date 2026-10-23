import SwiftUI
import AppKit
import CleanYourMacCore

/// Troca as telas do módulo Agentes de IA conforme a fase do fluxo.
struct AgentsModuleView: View {
    @State var model: AgentsFlowModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                AgentsIntroView(model: model).transition(.stage)
            case .scanning:
                AgentsScanningView(model: model).transition(.stage)
            case .results:
                AgentsResultsView(model: model).transition(.stage)
            case .nothingFound:
                AgentsNothingFoundView(model: model).transition(.stage)
            case .removing:
                AgentsRemovingView().transition(.stage)
            case .done(let outcome):
                AgentsDoneView(model: model, outcome: outcome).transition(.stage)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        #if DEBUG
        .task { await AgentsDebugAutomation.run(model) }
        #endif
    }
}

extension AgentsFlowModel.Section {
    var symbol: String {
        switch self {
        case .worktrees: "arrow.triangle.branch"
        case .sessions: "bubble.left.and.bubble.right.fill"
        }
    }
}

struct AgentsIntroView: View {
    var model: AgentsFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .agents, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 18) {
                Text("agents.intro.title").font(Theme.display(46))
                Text("agents.intro.subtitle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AgentsFlowModel.Section.allCases, id: \.self) { s in
                        HStack(spacing: 14) {
                            CategoryBadge(symbol: s.symbol, module: .agents)
                            Text(LocalizedStringKey.dynamic("agents.category.\(s.rawValue)")).font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 10)
                Label("agents.intro.safety", systemImage: "lock.shield.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.scan", module: .agents, action: model.start)
        }
    }
}

struct AgentsScanningView: View {
    var model: AgentsFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .agents, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("agents.scan.title").font(Theme.display(34))
                Text(LocalizedStringKey.dynamic("agents.scan.step.\(model.scanStep ?? "worktrees")"))
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: model.scanStep)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.stop", module: .agents, action: model.stop)
        }
    }
}

struct AgentsNothingFoundView: View {
    var model: AgentsFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .agents, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text("agents.nothing.title").font(Theme.display(40))
                Text("agents.nothing.message").font(.system(size: 17)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .agents, action: model.restart)
        }
    }
}

struct AgentsRemovingView: View {
    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .agents, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("agents.removing.title").font(Theme.display(34))
                ProgressView().controlSize(.small).tint(.white)
            }
        } action: {
            EmptyView()
        }
    }
}

/// Fim da remoção: quanto saiu, que o espaço volta ao esvaziar o Lixo, o que falhou e Revisar Mais Itens.
struct AgentsDoneView: View {
    var model: AgentsFlowModel
    var outcome: AgentsFlowModel.Outcome
    @Environment(\.locale) private var locale

    private var failed: Bool { !outcome.failed.isEmpty }

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .agents, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text(LocalizedStringKey(failed ? "agents.done.partial.title" : "agents.done.title")).font(Theme.display(38))
                Text(summary)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if outcome.removed > 0 && !model.dryRun {
                    Text("agents.done.trash").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                }
                if failed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(outcome.failed.sorted { $0.key < $1.key }, id: \.key) { id, reason in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: AgentsText.targetName(id))
                                        .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                    Text(FailureText.describe(reason)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                HStack(spacing: 10) {
                    if !(model.report?.isEmpty ?? true) {
                        Button("agents.done.reviewMore") { model.reviewMore() }
                            .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                            .fixedSize()
                    }
                    Button("apps.done.openTrash") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                    }
                    .buttonStyle(GlassButtonStyle(size: .large))
                    .fixedSize()
                    Button("apps.done.log") { NSWorkspace.shared.open(CleanupLog.standard.directory) }
                        .buttonStyle(GlassButtonStyle(size: .large))
                        .fixedSize()
                }
                .padding(.top, 6)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .agents, action: model.restart)
        }
    }

    private var summary: String {
        let size = SizeFormatter.string(outcome.freed, locale: locale)
        let base = model.dryRun ? "agents.done.dryRun" : "agents.done.summary"
        let key = base + (outcome.removed == 1 ? ".one" : ".other")
        return String(format: NSLocalizedString(key, comment: ""), outcome.removed, size)
    }
}

/// Textos de exibição do módulo (nomes de agentes, projetos, alvos).
enum AgentsText {
    static func agentName(_ id: String) -> String {
        AgentsCatalog.agents.first { $0.id == id }?.name ?? id
    }

    /// Reserva quando não há `cwd`. Pasta crua do projeto do Claude Code (`-Users-x-Projetos-Y`) → `~/Projetos/Y`; `--` vira
    /// `/.` (pasta oculta, como `.claude`). Só exibição: nomes com hífen saem errados. Gemini (hash): "Projeto 1a2b3c4d".
    static func projectName(_ raw: String, agent: String) -> String {
        if raw.hasPrefix("-") {
            let path = raw.replacingOccurrences(of: "--", with: "/.").replacingOccurrences(of: "-", with: "/")
            return (path as NSString).abbreviatingWithTildeInPath
        }
        if agent == "gemini" {
            return String(format: NSLocalizedString("agents.project.hash", comment: ""), String(raw.prefix(8)))
        }
        return raw
    }

    /// Rótulo do projeto da sessão: o `cwd` do `.jsonl` abreviado com `~`; sem ele, o nome da pasta decodificado.
    static func projectLabel(_ s: AgentSession) -> String? {
        if let cwd = s.workingDirectory { return (cwd as NSString).abbreviatingWithTildeInPath }
        return s.project.map { projectName($0, agent: s.agent) }
    }

    /// Caminho abreviado com `~`, ou "Agente · id curto" para uma sessão (`<agente>:<sessão>`).
    static func targetName(_ id: String) -> String {
        if id.hasPrefix("/") { return (id as NSString).abbreviatingWithTildeInPath }
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return id }
        return agentName(parts[0]) + " · " + parts[1]
    }
}

#if DEBUG
/// `CYM_AGENTS_AUTO=scan|results|worktrees|sessions|done` leva o fluxo até a tela pedida (capturas). `done` passa pela
/// remoção, que no Debug é simulada (só `CYM_DRY_RUN=0` remove de verdade). `CYM_AGENTS_AUTOSELECT=1` marca os cartões
/// da seção aberta.
@MainActor
enum AgentsDebugAutomation {
    static func run(_ model: AgentsFlowModel) async {
        let env = ProcessInfo.processInfo.environment
        guard let target = env["CYM_AGENTS_AUTO"] else { return }
        model.start()
        guard target != "scan" else { return }
        while model.phase == .scanning { try? await Task.sleep(for: .milliseconds(50)) }
        if let section = AgentsFlowModel.Section(rawValue: target) {
            model.openManager(section, autoselect: env["CYM_AGENTS_AUTOSELECT"] == "1")
        }
        if target == "done", model.dryRun, let tile = model.report?.tiles.first {
            model.cleanTile(tile)
            model.confirmRemoval()
        }
    }
}
#endif
