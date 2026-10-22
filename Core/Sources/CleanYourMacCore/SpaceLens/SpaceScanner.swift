import Foundation

/// Varre uma pasta (ou o disco) e monta a árvore com tamanhos alocados. Não segue links; pastas excluídas (outros
/// volumes, `/System/Volumes`…) ficam de fora. As primeiras camadas são lidas em série e cada subárvore abaixo delas
/// roda num `fts` próprio, em paralelo (sem `chdir`, que não é seguro entre threads).
public struct SpaceScanner: Sendable {
    public struct Options: Sendable {
        /// Até que profundidade dividir a varredura em tarefas paralelas (0 = uma só).
        public var splitDepth: Int
        /// (caminho, dispositivo) → a pasta não entra na análise.
        public var isExcluded: @Sendable (String, dev_t) -> Bool

        public init(splitDepth: Int = 2, isExcluded: @escaping @Sendable (String, dev_t) -> Bool = { _, _ in false }) {
            self.splitDepth = splitDepth
            self.isExcluded = isExcluded
        }
    }

    public let options: Options

    public init(options: Options = Options()) { self.options = options }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        private var stopped = false
        func add(_ n: Int) -> Int { lock.withLock { value += n; return value } }
        var total: Int { lock.withLock { value } }
        func stop() { lock.withLock { stopped = true } }
        var isStopped: Bool { lock.withLock { stopped } }
    }

    /// `progress` recebe quantos itens já foram lidos (de tempos em tempos, de qualquer thread).
    public func scan(_ url: URL, isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled },
                     progress: (@Sendable (Int) -> Void)? = nil) throws -> SpaceNode {
        let path = PathPolicy.lexicalPath(url.path)
        var st = stat()
        guard lstat(path, &st) == 0 else { throw CocoaError(.fileNoSuchFile) }
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let root = SpaceNode(name: (path as NSString).lastPathComponent, isDirectory: isDir, size: Int64(st.st_blocks) * 512, rootPath: path)
        guard isDir else { return root }

        let counter = Counter()
        var tasks: [(SpaceNode, String)] = []
        if options.splitDepth == 0 {
            tasks = [(root, path)]
        } else {
            try expand(root, path, depth: 0, tasks: &tasks, counter: counter, isCancelled: isCancelled)
        }
        let list = tasks
        DispatchQueue.concurrentPerform(iterations: list.count) { i in
            walk(list[i].0, list[i].1, counter: counter, isCancelled: isCancelled, progress: progress)
        }
        if counter.isStopped || isCancelled() { throw CancellationError() }
        root.finalize()
        return root
    }

    /// Lê as primeiras camadas em série; as pastas na profundidade `splitDepth` viram tarefas do `fts`.
    private func expand(_ node: SpaceNode, _ path: String, depth: Int, tasks: inout [(SpaceNode, String)], counter: Counter,
                        isCancelled: () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
        guard let dir = opendir(path) else {
            node.isUnreadable = true
            return
        }
        defer { closedir(dir) }
        var entries = 0
        while let e = readdir(dir) {
            let name = withUnsafeBytes(of: e.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(e.pointee.d_namlen)), as: UTF8.self)
            }
            guard name != ".", name != ".." else { continue }
            let child = path == "/" ? "/" + name : path + "/" + name
            var st = stat()
            guard lstat(child, &st) == 0 else { continue }
            let isDir = (st.st_mode & S_IFMT) == S_IFDIR
            if isDir, options.isExcluded(child, st.st_dev) { continue }
            let n = SpaceNode(name: name, isDirectory: isDir, size: Int64(st.st_blocks) * 512)
            node.append(n)
            entries += 1
            guard isDir else { continue }
            if depth + 1 < options.splitDepth {
                try expand(n, child, depth: depth + 1, tasks: &tasks, counter: counter, isCancelled: isCancelled)
            } else {
                tasks.append((n, child))
            }
        }
        _ = counter.add(entries)
    }

    /// Uma subárvore com `fts`: monta os nós abaixo de `node` (que já existe).
    private func walk(_ node: SpaceNode, _ path: String, counter: Counter, isCancelled: @Sendable () -> Bool,
                      progress: (@Sendable (Int) -> Void)?) {
        guard !counter.isStopped else { return }
        let fts: UnsafeMutablePointer<FTS>? = path.withCString { p in
            var argv: [UnsafeMutablePointer<CChar>?] = [strdup(p), nil]
            defer { free(argv[0]) }
            return fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil)
        }
        guard let fts else {
            node.isUnreadable = true
            return
        }
        defer { fts_close(fts) }
        // stack[nível] = pasta aberta nesse nível (nível 0 = a raiz da tarefa).
        var stack: [SpaceNode] = [node]
        var seen = 0
        while let e = fts_read(fts) {
            let level = Int(e.pointee.fts_level)
            let info = Int32(e.pointee.fts_info)
            if level == 0 {
                if info == FTS_DNR || info == FTS_ERR { node.isUnreadable = true }
                continue
            }
            if info == FTS_DP { continue }
            seen += 1
            if seen & 0xFFF == 0 {
                if isCancelled() { counter.stop() }
                if counter.isStopped { return }
                let total = counter.add(0x1000)
                progress?(total)
            }
            // fts_name é um vetor de tamanho variável; o nome é o fim de fts_path.
            let name = String(cString: e.pointee.fts_path + Int(e.pointee.fts_pathlen) - Int(e.pointee.fts_namelen))
            let parent = stack[min(level - 1, stack.count - 1)]
            let st = e.pointee.fts_statp
            switch info {
            case FTS_D:
                if let st, options.isExcluded(String(cString: e.pointee.fts_path), st.pointee.st_dev) {
                    fts_set(fts, e, FTS_SKIP)
                    seen -= 1
                    continue
                }
                let n = SpaceNode(name: name, isDirectory: true, size: st.map { Int64($0.pointee.st_blocks) * 512 } ?? 0)
                parent.append(n)
                if stack.count > level { stack.removeSubrange(level...) }
                stack.append(n)
            case FTS_DNR, FTS_ERR:
                let n = SpaceNode(name: name, isDirectory: true, size: 0)
                n.isUnreadable = true
                parent.append(n)
            case FTS_DC:
                continue
            default:
                parent.append(SpaceNode(name: name, isDirectory: false, size: st.map { Int64($0.pointee.st_blocks) * 512 } ?? 0))
            }
        }
        _ = counter.add(seen & 0xFFF)
    }
}
