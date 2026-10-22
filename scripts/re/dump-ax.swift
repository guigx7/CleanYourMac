// Despeja a árvore de Acessibilidade da janela do CleanMyMac (observação da UI).
// Uso: swift scripts/re/dump-ax.swift <rótulo>  → re-notes/ax/<rótulo>-<timestamp>.txt
// Requer: Terminal (ou o app que roda o script) em Ajustes > Privacidade > Acessibilidade.
import AppKit
import ApplicationServices

let label = CommandLine.arguments.dropFirst().first ?? "screen"
let bundleIDs = ProcessInfo.processInfo.environment["CYM_AX_BUNDLE"].map { [$0] } ?? ["com.macpaw.CleanMyMac-setapp", "com.macpaw.CleanMyMac5"]

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write("Sem permissão de Acessibilidade para este terminal.\n".data(using: .utf8)!)
    exit(1)
}
guard let app = NSWorkspace.shared.runningApplications.first(where: { bundleIDs.contains($0.bundleIdentifier ?? "") }) else {
    FileHandle.standardError.write("CleanMyMac não está aberto.\n".data(using: .utf8)!)
    exit(1)
}

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
}

func text(_ el: AXUIElement) -> String {
    let parts = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
        .compactMap { attr(el, $0) as? String }
        .filter { !$0.isEmpty }
    return parts.joined(separator: " | ")
}

var lines: [String] = []
func walk(_ el: AXUIElement, depth: Int) {
    guard depth < 60 else { return }
    let role = attr(el, kAXRoleAttribute) as? String ?? "?"
    let t = text(el)
    var mark = ""
    if let v = attr(el, kAXValueAttribute) as? NSNumber, role == kAXCheckBoxRole { mark = " [checked=\(v)]" }
    // Linhas de listas em árvore: o nível mostra quem é filho de quem.
    if role == kAXRowRole, let level = attr(el, kAXDisclosureLevelAttribute) as? NSNumber { mark = " [level=\(level)]" }
    if !t.isEmpty || role == kAXCheckBoxRole || !mark.isEmpty {
        lines.append(String(repeating: "  ", count: depth) + role + mark + ": " + t)
    }
    for child in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        walk(child, depth: depth + 1)
    }
}

let root = AXUIElementCreateApplication(app.processIdentifier)
// Listas grandes deixam o app lento para responder: o padrão (6 s) devolveria uma árvore vazia.
AXUIElementSetMessagingTimeout(root, 60)

// --press "<título exato>": clica num elemento de navegação antes do dump.
// Nunca clica em nada que limpe/remova (regra de ouro: só análise no CleanMyMac).
let forbidden = ["limpar", "clean", "remov", "esvaziar", "empty", "apagar", "delete", "desinstalar", "uninstall",
                 "atualizar", "update", "instalar", "install", "redefinir", "reset",
                 "executar", "run", "liberar", "free up", "diminuir", "thin", "reindexar", "reindex", "acelerar", "speed up",
                 "reparar", "repair", "desativar", "disable", "esvaziar cache", "flush"]
if let i = CommandLine.arguments.firstIndex(of: "--press"), i + 1 < CommandLine.arguments.count {
    let target = CommandLine.arguments[i + 1]
    // CYM_AX_ALLOW_ACTIONS=1 libera ações só no nosso app (teste real controlado); no CleanMyMac, nunca.
    let ownApp = app.bundleIdentifier == "io.github.guigx7.CleanYourMac" && ProcessInfo.processInfo.environment["CYM_AX_ALLOW_ACTIONS"] == "1"
    guard ownApp || !forbidden.contains(where: { target.lowercased().contains($0) }) else {
        FileHandle.standardError.write("Recusado: '\(target)' parece uma ação de limpeza.\n".data(using: .utf8)!)
        exit(2)
    }
    // --last: usa a última ocorrência (ex.: o botão de um diálogo, depois do da barra).
    let useLast = CommandLine.arguments.contains("--last")
    var matches: [AXUIElement] = []
    func find(_ el: AXUIElement, depth: Int) {
        guard depth < 60 else { return }
        let names = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { attr(el, $0) as? String }
        if names.contains(target) { matches.append(el) }
        for child in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { find(child, depth: depth + 1) }
    }
    find(root, depth: 0)
    // --index N: usa a N-ésima ocorrência (0 = primeira), ex.: o botão de detalhe da N-ésima linha.
    var indexed: AXUIElement?
    if let j = CommandLine.arguments.firstIndex(of: "--index"), j + 1 < CommandLine.arguments.count,
       let n = Int(CommandLine.arguments[j + 1]), n >= 0, n < matches.count { indexed = matches[n] }
    guard let hit = indexed ?? (useLast ? matches.last : matches.first) else {
        FileHandle.standardError.write("Elemento '\(target)' não encontrado.\n".data(using: .utf8)!)
        exit(3)
    }
    var actions: CFArray?
    AXUIElementCopyActionNames(hit, &actions)
    // --double: clique duplo com o mouse (ex.: entrar numa pasta da Lupa de Espaço), mesmo se o elemento aceitar AXPress.
    let double = CommandLine.arguments.contains("--double")
    if !double && ((actions as? [String]) ?? []).contains(kAXPressAction) {
        AXUIElementPerformAction(hit, kAXPressAction as CFString)
    } else {
        // Texto dentro de uma linha: clica com o mouse no centro dele, como uma pessoa faria.
        guard let posValue = attr(hit, kAXPositionAttribute), let sizeValue = attr(hit, kAXSizeAttribute) else {
            FileHandle.standardError.write("Elemento '\(target)' sem posição.\n".data(using: .utf8)!)
            exit(3)
        }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        let center = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        // Confere o que está de fato sob o ponto antes de clicar.
        var under: AXUIElement?
        AXUIElementCopyElementAtPosition(root, Float(center.x), Float(center.y), &under)
        // Sobe do elemento sob o ponto até o primeiro botão: é ele que receberia o clique.
        var probe = under
        while let p = probe, (attr(p, kAXRoleAttribute) as? String) != kAXButtonRole, let parent = attr(p, kAXParentAttribute) {
            probe = (parent as! AXUIElement)
        }
        let isButton = probe.map { (attr($0, kAXRoleAttribute) as? String) == kAXButtonRole } ?? false
        let underText = isButton ? (probe.map { text($0).lowercased() } ?? "") : ""
        guard ownApp || !forbidden.contains(where: { underText.contains($0) }) else {
            FileHandle.standardError.write("Recusado: sob o ponto está '\(underText)'.\n".data(using: .utf8)!)
            exit(2)
        }
        app.activate()
        Thread.sleep(forTimeInterval: 0.3)
        for click in 1...(double ? 2 : 1) {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: center, mouseButton: .left)
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                e?.post(tap: .cghidEventTap)
            }
        }
    }
    Thread.sleep(forTimeInterval: 1.5)
}

for window in (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    lines.append("== window: " + text(window))
    walk(window, depth: 1)
}

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let dir = repo.appendingPathComponent("re-notes/ax")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
let file = dir.appendingPathComponent("\(label)-\(stamp).txt")
try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
print("\(lines.count) linhas → \(file.path)")
