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

@Test func appleScriptRunnerSupportsNewCommands() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cym-trash-\(UUID())")
    let trash = root.appendingPathComponent(".Trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    var srcs: [URL] = []
    for (i, name) in ["it's", "a b", "$(id)", "x"].enumerated() {
        let dir = root.appendingPathComponent("src\(i)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: f)
        srcs.append(f)
    }
    let dup = root.appendingPathComponent("src9/x")
    try FileManager.default.createDirectory(at: dup.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("y".utf8).write(to: dup)
    srcs.append(dup)

    var tools = AppleScriptPrivilegedRunner.Tools()
    tools.trash = trash.path
    tools.uid = getuid()
    tools.launchctl = "/bin/echo"
    tools.pkgutil = "/bin/echo"
    let cmds = srcs.map { PrivilegedCommand.trash($0, owner: "com.example.a") }
        + [.launchdBootout(plist: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.a.plist"), owner: "com.example.a"),
           .launchdBootout(plist: URL(fileURLWithPath: "/Library/LaunchAgents/com.example.a.agent.plist"), owner: "com.example.a"),
           .forgetPackage("com.example.pkg", owner: "com.example.a"),
           .forgetPackage("bad id;rm", owner: "com.example.a")]
    let script = AppleScriptPrivilegedRunner.makeScript(cmds, tools: tools)
    let file = root.appendingPathComponent("s.sh")
    try script.write(to: file, atomically: true, encoding: .utf8)
    #expect(try sh(["-n", file.path]).0 == 0)
    let (status, output) = try sh([file.path])
    #expect(status == 0)
    for i in 0..<(srcs.count + 3) { #expect(output.contains("CYM:\(i):ok"), "comando \(i)") }
    #expect(output.contains("CYM:\(srcs.count + 3):fail"))
    for s in srcs { #expect(!FileManager.default.fileExists(atPath: s.path)) }
    for name in ["it's", "a b", "$(id)", "x", "x 2"] {
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent(name).path), "\(name)")
    }
    #expect(output.contains("bootout system /Library/LaunchDaemons/com.example.a.plist"))
    #expect(output.contains("bootout gui/\(getuid()) /Library/LaunchAgents/com.example.a.agent.plist"))
    #expect(output.contains("--forget com.example.pkg"))
}
