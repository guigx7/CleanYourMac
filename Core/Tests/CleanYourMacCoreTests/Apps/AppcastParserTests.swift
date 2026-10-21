import Foundation
import Testing
@testable import CleanYourMacCore

/// Appcast escrito por nós, no formato público do Sparkle (RSS 2.0 + namespace sparkle).
private let appcast = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<item>
  <title>1.2</title>
  <pubDate>Tue, 20 Oct 2026 10:00:00 +0000</pubDate>
  <sparkle:version>120</sparkle:version>
  <sparkle:shortVersionString>1.2</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <description><![CDATA[<ul><li>Correções &amp; melhorias</li></ul>]]></description>
  <enclosure url="https://example.com/Foo-1.2.zip" length="1234" type="application/octet-stream" sparkle:edSignature="sig"/>
  <sparkle:deltas><enclosure url="https://example.com/d.delta" sparkle:deltaFrom="110" length="10"/></sparkle:deltas>
</item>
<item>
  <title>1.3 beta</title>
  <sparkle:channel>beta</sparkle:channel>
  <sparkle:version>130</sparkle:version>
  <enclosure url="https://example.com/Foo-1.3.zip" length="1"/>
</item>
<item>
  <title>2.0</title>
  <sparkle:version>200</sparkle:version>
  <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
  <enclosure url="https://example.com/Foo-2.0.zip" length="1"/>
</item>
<item>
  <title>1.1 (Sparkle 1)</title>
  <enclosure url="https://example.com/Foo-1.1.zip" length="9" sparkle:version="110" sparkle:shortVersionString="1.1"/>
</item>
<item>
  <title>sem versão</title>
  <enclosure url="https://example.com/Foo-x.zip" length="9"/>
</item>
</channel>
</rss>
"""

@Suite struct AppcastParserTests {
    @Test func parsesSparkle2Appcast() throws {
        let items = try AppcastParser.parse(Data(appcast.utf8))
        #expect(items.count == 4) // o item sem sparkle:version é descartado
        let first = try #require(items.first)
        #expect(first.version == "120")
        #expect(first.shortVersion == "1.2")
        #expect(first.minimumSystemVersion == "14.0")
        #expect(first.downloadURL == URL(string: "https://example.com/Foo-1.2.zip"))
        #expect(first.length == 1234)
        #expect(first.edSignature == "sig")
        #expect(first.notes == "Correções & melhorias")
        #expect(first.date != nil)
        #expect(items[3].version == "110")
        #expect(items[3].shortVersion == "1.1")
    }

    @Test func bestSkipsDeltaBetaAndTooNew() throws {
        let items = try AppcastParser.parse(Data(appcast.utf8))
        let best = AppcastParser.best(items, systemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                                      arch: "arm64")
        #expect(best?.version == "120")
        #expect(best?.downloadURL == URL(string: "https://example.com/Foo-1.2.zip"))
    }

    @Test func malformedAppcastIgnored() {
        #expect(throws: (any Error).self) { try AppcastParser.parse(Data("<rss><channel><item>".utf8)) }
        #expect(AppcastParser.best([], systemVersion: ProcessInfo.processInfo.operatingSystemVersion, arch: "arm64") == nil)
    }
}
