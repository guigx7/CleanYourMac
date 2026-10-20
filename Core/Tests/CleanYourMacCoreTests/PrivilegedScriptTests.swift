import Testing
import Foundation
@testable import CleanYourMacCore

private let hostile = ["/tmp/a b", "/tmp/it's", "/tmp/$(rm -rf ~)", "/tmp/ação 🧹", "/tmp/`id`", "/tmp/x\"y"]

private func sh(_ args: [String]) throws -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    try p.run()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}

@Test func quotesHostilePaths() throws {
    let cmds = hostile.map { PrivilegedCommand.remove(URL(fileURLWithPath: $0)) }
    let script = AppleScriptPrivilegedRunner.makeScript(cmds)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("cym-\(UUID()).sh")
    try script.write(to: file, atomically: true, encoding: .utf8)
    #expect(try sh(["-n", file.path]).0 == 0)

    // Troca o rm por echo: a saída deve listar exatamente os caminhos, sem expansão.
    let echoScript = AppleScriptPrivilegedRunner.makeScript(cmds, tools: .init(rm: "/bin/echo"))
    try echoScript.write(to: file, atomically: true, encoding: .utf8)
    let (status, output) = try sh([file.path])
    #expect(status == 0)
    for path in hostile { #expect(output.contains("-rf -- \(path)\n")) }
    for i in hostile.indices { #expect(output.contains("CYM:\(i):ok")) }
}

@Test func parsesResults() {
    let out = "CYM:0:ok\nnoise\nCYM:1:fail\n"
    let results = AppleScriptPrivilegedRunner.parse(out, count: 3)
    #expect((try? results[0].get()) != nil)
    #expect((try? results[1].get()) == nil)
    #expect((try? results[2].get()) == nil)
}
