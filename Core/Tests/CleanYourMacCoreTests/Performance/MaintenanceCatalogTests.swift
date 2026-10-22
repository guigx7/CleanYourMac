import Foundation
import Testing
@testable import CleanYourMacCore

struct FakeMaintenanceFacts: MaintenanceFacts {
    var osVersion = (major: 26, minor: 6)
    var isAppleSilicon = true
    var isBootVolumeAPFS = true
    var mailLibraryExists = true
    var purgeableEstimateBytes: Int64 = 3_800_000_000
    var isSpotlightIndexingEnabled = true
    var periodicToolExists = false
    var localTimeMachineSnapshots: [String] = []
}

@Suite struct MaintenanceCatalogTests {
    func applicable(_ facts: FakeMaintenanceFacts) -> [MaintenanceTaskID] {
        MaintenanceCatalog(facts: facts).tasks().filter(\.isApplicable).map(\.id)
    }

    @Test func applicableTasksOnThisMachineShape() {
        #expect(applicable(FakeMaintenanceFacts()) == [.speedUpMail, .flushDNS, .freeUpPurgeable, .reindexSpotlight, .repairPermissions])
    }

    @Test func allTasksListedInOrder() {
        #expect(MaintenanceCatalog(facts: FakeMaintenanceFacts()).tasks().map(\.id) == MaintenanceTaskID.allCases)
    }

    @Test func freeUpRAMOnlyOnIntel() {
        var f = FakeMaintenanceFacts()
        #expect(!applicable(f).contains(.freeUpRAM))
        f.isAppleSilicon = false
        #expect(applicable(f).contains(.freeUpRAM))
    }

    @Test func periodicScriptsBeforeSonomaWithTool() {
        var f = FakeMaintenanceFacts()
        f.periodicToolExists = true
        #expect(!applicable(f).contains(.periodicScripts))
        f.osVersion = (13, 6)
        #expect(applicable(f).contains(.periodicScripts))
        f.periodicToolExists = false
        #expect(!applicable(f).contains(.periodicScripts))
    }

    @Test func thinSnapshotsNeedsAPFSAndSnapshot() {
        var f = FakeMaintenanceFacts()
        f.localTimeMachineSnapshots = ["com.apple.TimeMachine.2026-10-22-010101.local"]
        #expect(applicable(f).contains(.thinSnapshots))
        f.isBootVolumeAPFS = false
        #expect(!applicable(f).contains(.thinSnapshots))
    }

    @Test func mailNeedsMailFolder() {
        var f = FakeMaintenanceFacts()
        f.mailLibraryExists = false
        #expect(!applicable(f).contains(.speedUpMail))
    }

    @Test func purgeableHiddenWhenNothingToRecover() {
        var f = FakeMaintenanceFacts()
        f.purgeableEstimateBytes = 0
        #expect(!applicable(f).contains(.freeUpPurgeable))
    }

    @Test func spotlightHiddenWhenIndexingOff() {
        var f = FakeMaintenanceFacts()
        f.isSpotlightIndexingEnabled = false
        #expect(!applicable(f).contains(.reindexSpotlight))
    }

    @Test func recommendedEqualsApplicable() {
        for t in MaintenanceCatalog(facts: FakeMaintenanceFacts()).tasks() {
            #expect(t.isRecommended == t.isApplicable)
        }
    }

    @Test func adminTasksFollowSpec() {
        let admin = MaintenanceCatalog(facts: FakeMaintenanceFacts()).tasks().filter(\.requiresAdmin).map(\.id)
        #expect(admin == [.flushDNS, .reindexSpotlight, .repairPermissions, .freeUpRAM, .periodicScripts])
    }

    @Test func purgeableDetailFromFacts() {
        let t = MaintenanceCatalog(facts: FakeMaintenanceFacts()).tasks().first { $0.id == .freeUpPurgeable }
        #expect(t?.detail == 3_800_000_000)
    }
}
