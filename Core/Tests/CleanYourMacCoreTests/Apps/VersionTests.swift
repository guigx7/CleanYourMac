import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct VersionTests {
    @Test func numericOrder() {
        #expect(Version.compare("10.4.14", "10.4.13") == .orderedDescending)
        #expect(Version.compare("1.10", "1.9") == .orderedDescending)
        #expect(Version.compare("2.0", "2.0") == .orderedSame)
        #expect(Version.compare("v2.1", "2.1") == .orderedSame)
    }

    /// Comparador do Sparkle: o mais longo vence, salvo quando o excedente começa com texto.
    @Test func sparkleSegmentRules() {
        #expect(Version.compare("2.0.0", "2.0") == .orderedDescending)
        #expect(Version.compare("1.0", "1.0b1") == .orderedDescending)
        #expect(Version.compare("1.0", "1.0a") == .orderedDescending)
        #expect(Version.compare("1.0b2", "1.0b1") == .orderedDescending)
    }

    @Test func incomparableVersionsSkipped() {
        #expect(Version.compare("", "1.0") == nil)
        #expect(Version.compare("latest", "1.0") == nil)
        #expect(Version.compare("1.0 beta", "1.0") == nil)
        #expect(Version.compare("20261020", "1.24") == nil)
        #expect(Version.compare("2026.10", "1.24") == nil)
        #expect(Version.compare("v0.2026.10.14.08.27.stable_02", "0.2026.10.07.08.27.stable_01") == nil)
        #expect(Version.compare(String(repeating: "1", count: 65), "1") == nil)
    }

    @Test func remotePrereleaseNotOfferedToStable() {
        #expect(Version.isUpdate(installed: "1.2", available: "1.3b1") == nil)
        #expect(Version.isUpdate(installed: "1.3b1", available: "1.3b2") == true)
        #expect(Version.isUpdate(installed: "1.2", available: "1.3") == true)
        #expect(Version.isUpdate(installed: "1.3", available: "1.3") == false)
        #expect(Version.isUpdate(installed: "1.4", available: "1.3") == false)
    }

    @Test func homebrewNormalization() {
        #expect(Version.isUpdate(installed: "1.104.0", available: "1.105.0,abcdef", homebrew: true) == true)
        #expect(Version.isUpdate(installed: "3.1.2", available: "3.1_2", homebrew: true) == false)
    }

    @Test func hugeNumbersComparedAsText() {
        #expect(Version.compare("1.1234567890123456789012", "1.1234567890123456789011") == .orderedDescending)
    }
}
