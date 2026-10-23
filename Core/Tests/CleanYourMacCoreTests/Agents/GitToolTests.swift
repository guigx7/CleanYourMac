import Foundation
import Testing
@testable import CleanYourMacCore

private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable { let executable: String; let arguments: [String] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    let responses: [String: (Int32, String)]
    let fallback: (Int32, String)

    init(responses: [String: (Int32, String)] = [:], fallback: (Int32, String) = (1, "")) {
        self.responses = responses
        self.fallback = fallback
    }

    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        lock.lock(); _calls.append(Call(executable: executable, arguments: arguments)); lock.unlock()
        let r = responses[arguments.joined(separator: " ")] ?? fallback
        return (r.0, r.1)
    }
}

@Suite struct GitToolTests {
    let clt = "/Library/Developer/CommandLineTools/usr/bin/git"
    let dev = "/Applications/Xcode.app/Contents/Developer"

    @Test func locatePrefersCommandLineTools() {
        let runner = RecordingRunner()
        let git = GitTool.locate(runner: runner, fileExists: { $0 == clt })
        #expect(git?.executable == clt)
    }

    @Test func locateUsesXcodeSelect() {
        let runner = RecordingRunner(responses: ["-p": (0, dev + "\n")])
        let git = GitTool.locate(runner: runner, fileExists: { $0 == dev + "/usr/bin/git" })
        #expect(git?.executable == dev + "/usr/bin/git")
    }

    @Test func locateNilWithoutDeveloperTools() {
        let runner = RecordingRunner(fallback: (2, "xcode-select: error"))
        let git = GitTool.locate(runner: runner, fileExists: { _ in false })
        #expect(git == nil)
        #expect(!runner.calls.contains { $0.executable == "/usr/bin/git" })
    }

    @Test func ignoredParsesOutput() {
        let wt = "/tmp/wt"
        let args = ["-C", wt, "check-ignore", "--", "dist", "build", "out"]
        let ok = RecordingRunner(responses: [args.joined(separator: " "): (0, "dist\nbuild\n")])
        let git = GitTool(executable: clt, runner: ok)
        #expect(git.ignored(["dist", "build", "out"], in: URL(fileURLWithPath: wt)) == ["dist", "build"])
        #expect(ok.calls == [.init(executable: clt, arguments: args)])

        let none = GitTool(executable: clt, runner: RecordingRunner(fallback: (1, "")))
        #expect(none.ignored(["dist", "build", "out"], in: URL(fileURLWithPath: wt)).isEmpty)
    }

    @Test func ignoredBatchesBy200() {
        let runner = RecordingRunner(fallback: (1, ""))
        let git = GitTool(executable: clt, runner: runner)
        _ = git.ignored((0..<450).map { "p\($0)" }, in: URL(fileURLWithPath: "/tmp/wt"))
        #expect(runner.calls.count == 3)
    }

    @Test func hasTrackedParses() {
        let wt = URL(fileURLWithPath: "/tmp/wt")
        let yes = GitTool(executable: clt, runner: RecordingRunner(fallback: (0, "dist/a.js\n")))
        let no = GitTool(executable: clt, runner: RecordingRunner(fallback: (0, "")))
        #expect(yes.hasTracked("dist", in: wt))
        #expect(!no.hasTracked("dist", in: wt))
    }
}
