import Foundation
import CleanYourMacCore

// cym — análise do CleanYourMac pela linha de comando (paridade e diagnóstico).
//
//   cym scan [--groups a,b] [--json] [--paths] [--home DIR --user NOME]
//   cym clean --dry-run [--groups a,b] [--recommended]
//   cym apps [--json] [--no-network]   (módulo Aplicativos; só leitura)
//
// Não existe limpeza de verdade pelo CLI: `clean` exige --dry-run.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"
if !args.isEmpty { args.removeFirst() }

@MainActor func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
@MainActor func has(_ flag: String) -> Bool { args.contains(flag) }

var context = ScanContext.current()
if let home = value("--home") {
    // Usado quando o cym roda como root para medir um usuário (análise privilegiada).
    let user = value("--user") ?? URL(fileURLWithPath: home).lastPathComponent
    context = ScanContext(root: context.root, home: URL(fileURLWithPath: home), userName: user,
                          preferredLanguages: context.preferredLanguages, now: Date(),
                          darwinUserCacheDir: value("--darwin").map { URL(fileURLWithPath: $0) })
}

let scanners = Registry.productionScanners()
var groups = Set(scanners.map(\.group))
if let list = value("--groups") {
    let requested = list.split(separator: ",").map(String.init)
    let unknown = requested.filter { GroupID(rawValue: $0) == nil }
    if !unknown.isEmpty { fail("grupos desconhecidos: \(unknown.joined(separator: ", "))") }
    groups = Set(requested.compactMap(GroupID.init(rawValue:)))
}

@MainActor func runScan() async throws -> ScanReport {
    for try await event in ScanEngine(scanners: scanners).scan(groups, context: context) {
        if case .finished(let report) = event { return report }
    }
    fail("análise não terminou")
}

/// Sem rede: nenhuma requisição sai (as fontes ficam sem resposta).
struct OfflineFetcher: HTTPFetcher {
    func get(_ url: URL, timeout: Duration) async throws -> Data { throw URLError(.notConnectedToInternet) }
}

switch command {
case "apps":
    let scan = has("--no-network") ? Registry.appsScan(fetcher: OfflineFetcher()) : Registry.appsScan()
    var appsReport: AppsReport?
    for try await event in scan.run(context) { if case .finished(let r) = event { appsReport = r } }
    guard let appsReport else { fail("análise não terminou") }
    let json = appsReport.parityJSON()
    if has("--json") {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        for item in appsReport.uninstaller {
            print(String(format: "%10@  %@", SizeFormatter.string(item.totalSize, locale: Locale(identifier: "pt-BR")), item.name))
        }
        print("filtros:", (json["filters"] as? [String: Int] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        print("atualizações:", appsReport.updates.updates.map { "\($0.name) \($0.installedVersion)→\($0.availableVersion) (\($0.source.rawValue))" },
              appsReport.updates.offline ? "[sem rede]" : "")
        print("sobras:", appsReport.leftovers.map { "\($0.name) \(SizeFormatter.string($0.totalSize, locale: Locale(identifier: "pt-BR")))" })
        print("instaladores:", appsReport.installers.map { "\($0.name) \(SizeFormatter.string($0.totalSize, locale: Locale(identifier: "pt-BR")))" })
    }
case "scan":
    let report = try await runScan()
    if has("--json") {
        var out: [String: Any] = ["tool": "cym", "version": CleanYourMacCore.version,
                                  "capturedAt": ISO8601DateFormatter().string(from: Date())]
        var groupsOut: [String: Any] = [:]
        for (g, result) in report.groups {
            groupsOut[g.rawValue] = [
                "totalBytes": result.totalSize,
                "items": result.items.map { item -> [String: Any] in
                    var entry: [String: Any] = ["name": item.name, "bytes": item.totalSize,
                                                "recommended": !item.leaves.isEmpty && item.leaves.allSatisfy { $0.isRecommended }]
                    if has("--paths") { entry["paths"] = item.leaves.compactMap { $0.url?.path } }
                    return entry
                },
            ]
        }
        out["groups"] = groupsOut
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        print()
    } else {
        for g in GroupID.allCases where report.groups[g] != nil {
            let r = report.groups[g]!
            print("\(g.rawValue): \(SizeFormatter.string(r.totalSize, locale: Locale(identifier: "pt-BR"))) em \(r.items.count) itens")
        }
        print("total: \(SizeFormatter.string(report.totalSize, locale: Locale(identifier: "pt-BR")))")
    }

case "clean":
    guard has("--dry-run") else { fail("o cym só simula a limpeza: use --dry-run") }
    let report = try await runScan()
    let items = has("--recommended") ? report.recommendedItems() : report.groups.values.flatMap(\.items)
    let logDir = FileManager.default.temporaryDirectory.appendingPathComponent("cym-dryrun")
    let engine = CleanEngine(policies: Registry.policies(for: scanners, context: context),
                             privileged: AppleScriptPrivilegedRunner(), dryRun: true, log: CleanupLog(directory: logDir))
    for await event in engine.clean(items) {
        switch event {
        case .finished(let item, .success(let bytes)): print("removeria \(item.url?.path ?? item.name) (\(bytes) B)")
        case .finished(let item, .failure(let f)): print("RECUSADO \(item.url?.path ?? item.name): \(f.reason)")
        case .completed(let r): print("total: \(SizeFormatter.string(r.freedBytes, locale: Locale(identifier: "pt-BR"))), \(r.failed.count) recusados")
        case .started: break
        }
    }

default:
    print("""
    uso:
      cym scan [--groups a,b] [--json] [--paths] [--home DIR --user NOME [--darwin DIR]]
      cym clean --dry-run [--groups a,b] [--recommended]
    grupos: \(GroupID.allCases.map(\.rawValue).joined(separator: ", "))
    """)
}
