import Testing
@testable import CleanYourMac

@Test func failureReasonsMapToKeys() {
    #expect(FailureText.key(for: "cancelled") == "reason.cancelled")
    #expect(FailureText.key(for: "in use") == "reason.inUse")
    #expect(FailureText.key(for: "signature would break; restored") == "reason.signature")
    #expect(FailureText.key(for: "path not allowed: /x") == "reason.permission")
    #expect(FailureText.key(for: "Operation not permitted") == "reason.permission")
    #expect(FailureText.key(for: "something odd") == "reason.unknown")
    #expect(FailureText.key(for: "timed out") == "reason.timedOut")
    #expect(FailureText.key(for: "item changed") == "reason.changed")
    #expect(FailureText.key(for: "open settings") == "reason.openSettings")
}

@MainActor @Test func failedItemsListed() async {
    let a = stubItem(.userCache, "a", 100)
    let m = makeModel([StubScanner(group: .userCache, items: [a])], failing: [a.id])
    m.startScan()
    await waitFor { m.phase == .results }
    m.clean(items: [a])
    await waitFor { if case .done = m.phase { true } else { false } }
    #expect(m.failedItems.map(\.0.id) == [a.id])
}
