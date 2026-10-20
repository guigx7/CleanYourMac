import Testing
import Foundation
@testable import CleanYourMacCore

@Test func acceptsChild() throws {
    let t = FixtureTree()
    let r = t.dir("R")
    let f = t.file("R/a/b", bytes: 1)
    #expect(try PathPolicy(allowedRoots: [r]).validate(f).path == f.path)
}

@Test func rejectsOutside() {
    let t = FixtureTree()
    let p = PathPolicy(allowedRoots: [t.dir("R")])
    #expect(throws: PathPolicyError.outsideAllowedRoots("/etc/hosts")) {
        try p.validate(URL(fileURLWithPath: "/etc/hosts"))
    }
}

@Test func rejectsDotDot() {
    let t = FixtureTree()
    let r = t.dir("R")
    t.file("x", bytes: 1)
    let sneaky = URL(fileURLWithPath: r.path + "/../x")
    #expect(throws: PathPolicyError.self) { try PathPolicy(allowedRoots: [r]).validate(sneaky) }
}

@Test func rejectsRootItself() {
    let t = FixtureTree()
    let r = t.dir("R")
    #expect(throws: PathPolicyError.isAllowedRootItself(r.path)) { try PathPolicy(allowedRoots: [r]).validate(r) }
}

@Test func rejectsSymlinkedParentEscape() {
    let t = FixtureTree()
    let outside = FixtureTree()
    outside.file("victim", bytes: 1)
    let r = t.dir("R")
    t.symlink("R/link", to: outside.root)
    let target = r.appendingPathComponent("link/victim")
    #expect(throws: PathPolicyError.symlinkEscape(target.path)) { try PathPolicy(allowedRoots: [r]).validate(target) }
}

@Test func acceptsSymlinkLeaf() throws {
    let t = FixtureTree()
    let outside = FixtureTree()
    let r = t.dir("R")
    let link = t.symlink("R/link", to: outside.root)
    #expect(try PathPolicy(allowedRoots: [r]).validate(link).path == link.path)
}

@Test func prefixTrick() {
    let t = FixtureTree()
    let r = t.dir("R/Caches")
    let evil = t.file("R/CachesEvil/x", bytes: 1)
    #expect(throws: PathPolicyError.outsideAllowedRoots(evil.path)) { try PathPolicy(allowedRoots: [r]).validate(evil) }
}

@Test func rootGivenThroughSymlinkStillMatches() throws {
    // /tmp -> /private/tmp: raízes e caminhos devem ser comparados já resolvidos.
    let t = FixtureTree()
    let r = t.dir("R")
    let f = t.file("R/a", bytes: 1)
    let viaTmp = URL(fileURLWithPath: r.path.replacingOccurrences(of: "/private/var", with: "/var"))
    #expect(try PathPolicy(allowedRoots: [viaTmp]).validate(f).path == f.path)
}

@Test func exactItemAllowedButNotSiblings() throws {
    let t = FixtureTree()
    let foo = t.dir("Logs/Foo")
    t.dir("Logs/Bar")
    let p = PathPolicy(allowedRoots: [], allowedItems: [foo])
    #expect(try p.validate(foo).path == foo.path)
    #expect(throws: PathPolicyError.self) { try p.validate(t.url("Logs/Bar")) }
    #expect(try p.validate(foo.appendingPathComponent("x")).path.hasSuffix("Logs/Foo/x"))
}
