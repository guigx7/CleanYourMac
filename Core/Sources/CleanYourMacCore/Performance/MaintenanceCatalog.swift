import CoreServices
import Foundation

/// Dados do sistema que as regras de docs/re/specs/performance/maintenance-tasks.md consultam (só leitura).
public protocol MaintenanceFacts: Sendable {
    var osVersion: (major: Int, minor: Int) { get }
    var isAppleSilicon: Bool { get }
    var isBootVolumeAPFS: Bool { get }
    /// `~/Library/Mail` existe.
    var mailLibraryExists: Bool { get }
    /// Bytes que o sistema estima liberar do volume de inicialização ("Até 3,8 GB").
    var purgeableEstimateBytes: Int64 { get }
    var isSpotlightIndexingEnabled: Bool { get }
    var periodicToolExists: Bool { get }
    /// Capturas `com.apple.TimeMachine.*` do volume de inicialização.
    var localTimeMachineSnapshots: [String] { get }
}

/// Regras de aplicabilidade e de recomendação das 8 tarefas.
public struct MaintenanceCatalog: Sendable {
    public static let adminTasks: Set<MaintenanceTaskID> = [.flushDNS, .reindexSpotlight, .repairPermissions, .freeUpRAM, .periodicScripts]

    public static func timeout(_ id: MaintenanceTaskID) -> Duration {
        switch id {
        case .flushDNS: .seconds(30)
        case .reindexSpotlight: .seconds(60)
        case .freeUpRAM: .seconds(120)
        case .speedUpMail, .freeUpPurgeable, .thinSnapshots: .seconds(600)
        case .repairPermissions, .periodicScripts: .seconds(1800)
        }
    }

    private let facts: any MaintenanceFacts

    public init(facts: any MaintenanceFacts) { self.facts = facts }

    /// As 8 tarefas, na ordem da lista; `isApplicable` diz quais aparecem.
    public func tasks() -> [MaintenanceTask] {
        MaintenanceTaskID.allCases.map { id in
            let applicable = isApplicable(id)
            return MaintenanceTask(id: id, isApplicable: applicable,
                                   // Spec §Recomendada: toda tarefa aplicável vem recomendada.
                                   isRecommended: applicable,
                                   requiresAdmin: Self.adminTasks.contains(id),
                                   detail: id == .freeUpPurgeable ? facts.purgeableEstimateBytes : nil,
                                   timeout: Self.timeout(id))
        }
    }

    private func isApplicable(_ id: MaintenanceTaskID) -> Bool {
        switch id {
        case .speedUpMail: facts.mailLibraryExists
        case .flushDNS, .repairPermissions: true
        case .freeUpPurgeable: facts.purgeableEstimateBytes > 0
        case .reindexSpotlight: facts.isSpotlightIndexingEnabled
        case .freeUpRAM: !facts.isAppleSilicon
        case .periodicScripts: facts.osVersion.major * 100 + facts.osVersion.minor < 1400 && facts.periodicToolExists
        case .thinSnapshots: facts.isBootVolumeAPFS && !facts.localTimeMachineSnapshots.isEmpty
        }
    }
}

/// Fatos lidos deste Mac.
public struct SystemMaintenanceFacts: MaintenanceFacts {
    public let osVersion: (major: Int, minor: Int)
    public let isAppleSilicon: Bool
    public let isBootVolumeAPFS: Bool
    public let mailLibraryExists: Bool
    public let purgeableEstimateBytes: Int64
    public let isSpotlightIndexingEnabled: Bool
    public let periodicToolExists: Bool
    public let localTimeMachineSnapshots: [String]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, commands: any CommandRunner = SystemCommandRunner()) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = (v.majorVersion, v.minorVersion)
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        isAppleSilicon = sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1
        var fs = statfs()
        isBootVolumeAPFS = statfs("/", &fs) == 0
            && withUnsafeBytes(of: fs.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } == "apfs"
        mailLibraryExists = FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Mail").path)
        purgeableEstimateBytes = Int64(clamping: CSDiskSpaceGetRecoveryEstimate(URL(fileURLWithPath: "/") as CFURL))
        // "/:\n\tIndexing enabled." quando ligado.
        isSpotlightIndexingEnabled = commands.run("/usr/bin/mdutil", ["-s", "/"]).output.contains("Indexing enabled")
        periodicToolExists = FileManager.default.isExecutableFile(atPath: "/usr/sbin/periodic")
        localTimeMachineSnapshots = TimeMachineSnapshotsList.parse(commands.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output)
    }
}

/// Saída de `tmutil listlocalsnapshots /`: uma linha por captura (a primeira é um cabeçalho).
enum TimeMachineSnapshotsList {
    static func parse(_ output: String) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }
    }
}
