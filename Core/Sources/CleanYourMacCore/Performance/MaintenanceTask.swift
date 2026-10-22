import Foundation

/// As 8 tarefas de manutenção do módulo Desempenho (ordem da lista do Gerenciador).
public enum MaintenanceTaskID: String, CaseIterable, Codable, Sendable {
    case speedUpMail, flushDNS, freeUpPurgeable, reindexSpotlight, repairPermissions, freeUpRAM, periodicScripts, thinSnapshots
}

/// Uma tarefa como a análise a encontrou neste Mac.
public struct MaintenanceTask: Identifiable, Hashable, Sendable {
    public let id: MaintenanceTaskID
    /// Aparece na lista do Gerenciador.
    public let isApplicable: Bool
    /// Conta no cartão "N tarefas recomendadas" (regra da spec).
    public let isRecommended: Bool
    public let requiresAdmin: Bool
    /// Valor exibido abaixo do nome (ex.: bytes purgáveis, "Até 3,8 GB").
    public let detail: Int64?
    public let timeout: Duration

    public init(id: MaintenanceTaskID, isApplicable: Bool, isRecommended: Bool, requiresAdmin: Bool,
                detail: Int64? = nil, timeout: Duration) {
        self.id = id
        self.isApplicable = isApplicable
        self.isRecommended = isRecommended
        self.requiresAdmin = requiresAdmin
        self.detail = detail
        self.timeout = timeout
    }
}
