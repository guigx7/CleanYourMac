import Foundation

/// Varre uma pasta (ou o disco) e monta a árvore com tamanhos alocados. Não segue links; pastas excluídas (outros
/// volumes, `/System/Volumes`…) ficam de fora. Várias threads tiram pastas de uma fila comum e leem cada uma com
/// `getattrlistbulk` (nome, tipo, dispositivo e tamanho alocado de todas as entradas numa só chamada).
public struct SpaceScanner: Sendable {
    public struct Options: Sendable {
        /// Threads de leitura.
        public var workers: Int
        /// (caminho, dispositivo) → a pasta não entra na análise.
        public var isExcluded: @Sendable (String, dev_t) -> Bool

        public init(workers: Int = max(2, ProcessInfo.processInfo.activeProcessorCount),
                    isExcluded: @escaping @Sendable (String, dev_t) -> Bool = { _, _ in false }) {
            self.workers = workers
            self.isExcluded = isExcluded
        }
    }

    public let options: Options

    public init(options: Options = Options()) { self.options = options }

    /// Fila de pastas a ler, com fim quando ela esvazia e ninguém está lendo.
    private final class WorkQueue: @unchecked Sendable {
        private let cond = NSCondition()
        private var pending: [(SpaceNode, String)] = []
        private var busy = 0
        private(set) var stopped = false
        private var count = 0

        init(_ first: (SpaceNode, String)) { pending = [first] }

        func next() -> (SpaceNode, String)? {
            cond.lock()
            defer { cond.unlock() }
            while pending.isEmpty && busy > 0 && !stopped { cond.wait() }
            guard !stopped, let item = pending.popLast() else {
                cond.broadcast()
                return nil
            }
            busy += 1
            return item
        }

        /// Termina uma pasta: entrega as subpastas achadas e quantos itens ela tinha.
        func done(_ found: [(SpaceNode, String)], items: Int) -> Int {
            cond.lock()
            defer { cond.unlock() }
            pending.append(contentsOf: found)
            busy -= 1
            count += items
            cond.broadcast()
            return count
        }

        func stop() {
            cond.lock()
            stopped = true
            cond.broadcast()
            cond.unlock()
        }
    }

    /// `progress` recebe quantos itens já foram lidos (de tempos em tempos, de qualquer thread).
    public func scan(_ url: URL, isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled },
                     progress: (@Sendable (Int) -> Void)? = nil) throws -> SpaceNode {
        let path = PathPolicy.lexicalPath(url.path)
        var st = stat()
        guard lstat(path, &st) == 0 else { throw CocoaError(.fileNoSuchFile) }
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let root = SpaceNode(name: (path as NSString).lastPathComponent, isDirectory: isDir, size: isDir ? 0 : Int64(st.st_blocks) * 512,
                             rootPath: path)
        guard isDir else { return root }
        let queue = WorkQueue((root, path))
        let workers = max(1, options.workers)
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            var reported = 0
            while let (node, dirPath) = queue.next() {
                if isCancelled() { queue.stop(); return }
                let (subdirs, items) = read(node, dirPath)
                let total = queue.done(subdirs, items: items)
                if let progress, total - reported >= 20_000 {
                    reported = total
                    progress(total)
                }
            }
        }
        if queue.stopped || isCancelled() { throw CancellationError() }
        root.finalize()
        return root
    }

    // MARK: - getattrlistbulk

    private static let bufferSize = 256 * 1024

    /// Lê as entradas de uma pasta, cria os nós e devolve as subpastas a visitar.
    private func read(_ node: SpaceNode, _ path: String) -> ([(SpaceNode, String)], Int) {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else {
            node.isUnreadable = true
            return ([], 0)
        }
        defer { close(fd) }
        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_ERROR)
        attrs.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        var subdirs: [(SpaceNode, String)] = []
        var items = 0
        while true {
            let n = getattrlistbulk(fd, &attrs, buffer, Self.bufferSize, 0)
            if n < 0 {
                node.isUnreadable = true
                break
            }
            if n == 0 { break }
            var entry = buffer
            for _ in 0..<n {
                let length = Int(entry.load(as: UInt32.self))
                defer { entry += length }
                var p = entry + 4
                let returned = p.loadUnaligned(as: attribute_set_t.self)
                p += MemoryLayout<attribute_set_t>.size
                // Na ordem dos bits: nome, dispositivo, tipo, erro; depois o tamanho alocado (arquivos).
                var name = ""
                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let ref = p.loadUnaligned(as: attrreference_t.self)
                    name = String(cString: (p + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    p += MemoryLayout<attrreference_t>.size
                }
                var dev: dev_t = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                    dev = p.loadUnaligned(as: dev_t.self)
                    p += MemoryLayout<dev_t>.size
                }
                var type: fsobj_type_t = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    type = p.loadUnaligned(as: fsobj_type_t.self)
                    p += MemoryLayout<fsobj_type_t>.size
                }
                var error: UInt32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                    error = p.loadUnaligned(as: UInt32.self)
                    p += MemoryLayout<UInt32>.size
                }
                var alloc: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    alloc = p.loadUnaligned(as: off_t.self)
                }
                guard !name.isEmpty, error == 0 else { continue }
                items += 1
                let childPath = path == "/" ? "/" + name : path + "/" + name
                if type == fsobj_type_t(VDIR.rawValue) {
                    if options.isExcluded(childPath, dev) {
                        items -= 1
                        continue
                    }
                    let child = SpaceNode(name: name, isDirectory: true, size: 0)
                    node.append(child)
                    subdirs.append((child, childPath))
                } else {
                    node.append(SpaceNode(name: name, isDirectory: false, size: alloc))
                }
            }
        }
        return (subdirs, items)
    }
}
