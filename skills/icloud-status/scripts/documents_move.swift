import Foundation
import Darwin

struct Failure: Error {
    let message: String
    let code: Int32
    init(_ message: String, _ code: Int32 = EINVAL) {
        self.message = message; self.code = code
    }
}
struct Fingerprint: Decodable {
    let dev: Int64
    let ino: UInt64
    let mode: UInt32
    let size: Int64
    let mtime_ns: Int64
}
struct Operation: Decodable {
    let kind: String
    let source: String
    let destination: String?
    let link_target: String?
    let expected: Fingerprint
}
struct Plan: Decodable {
    let schema: Int
    let source: String
    let target: String
    let requires_icloud_target: Bool?
    let directories: [String: Fingerprint]
    let operations: [Operation]
}

func emit(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}
func validPath(_ path: String) -> Bool {
    path.hasPrefix("/") && path != "/" && !path.contains("\0") &&
    !path.hasSuffix("/") && !path.split(separator: "/", omittingEmptySubsequences: false)
        .dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
}
func within(_ path: String, _ root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
}
func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
func leaf(_ path: String) -> String { (path as NSString).lastPathComponent }
func fileType(_ mode: UInt32) -> UInt32 { mode & UInt32(S_IFMT) }
func fingerprintMatches(_ st: stat, _ expected: Fingerprint, mutableDirectory: Bool) -> Bool {
    guard Int64(st.st_dev) == expected.dev, UInt64(st.st_ino) == expected.ino,
          fileType(UInt32(st.st_mode)) == fileType(expected.mode) else { return false }
    if mutableDirectory && fileType(expected.mode) == UInt32(S_IFDIR) { return true }
    let modified = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
    if fileType(expected.mode) == UInt32(S_IFDIR) { return modified == expected.mtime_ns }
    return Int64(st.st_size) == expected.size && modified == expected.mtime_ns
}
func descriptorStat(_ fd: Int32) throws -> stat {
    var result = stat()
    guard fstat(fd, &result) == 0 else { throw Failure("directory_stat_failed", errno) }
    return result
}
// Walk from / through directory descriptors: no parent component may be a symlink.
func openDirectory(_ path: String, identities: [String: Fingerprint] = [:]) throws -> Int32 {
    guard path == "/" || validPath(path) else { throw Failure("invalid_directory_path") }
    var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard fd >= 0 else { throw Failure("open_root_failed", errno) }
    do {
        var absolute = ""
        for component in path.split(separator: "/") {
            let next = openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw Failure("unsafe_or_unreadable_parent", errno) }
            close(fd); fd = next; absolute += "/" + component
            if let expected = identities[absolute] {
                guard fingerprintMatches(try descriptorStat(fd), expected, mutableDirectory: true) else {
                    throw Failure("directory_identity_changed", ESTALE)
                }
            }
        }
        // Reject aliases and case substitutions, including filesystem-root aliases.
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) == 0 else { throw Failure("directory_path_unavailable", errno) }
        guard String(cString: buffer) == path else { throw Failure("noncanonical_directory_path") }
        return fd
    } catch { close(fd); throw error }
}
func verifyDescriptorPath(_ fd: Int32, _ path: String) throws {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard fcntl(fd, F_GETPATH, &buffer) == 0 else { throw Failure("directory_path_unavailable", errno) }
    guard String(cString: buffer) == path else { throw Failure("directory_moved_during_operation", ESTALE) }
}
func entryStat(_ directory: Int32, _ name: String) throws -> stat {
    var result = stat()
    guard fstatat(directory, name, &result, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw Failure("source_stat_failed", errno)
    }
    return result
}
func verifyCloudScope(_ plan: Plan) throws {
    // Foundation exposes this status without reading or downloading file contents.
    let sourceCloud = try? URL(fileURLWithPath: plan.source)
        .resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem
    let targetCloud = try? URL(fileURLWithPath: plan.target)
        .resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem
    let requiresCloud = plan.requires_icloud_target == true || sourceCloud == true ||
        plan.target == NSHomeDirectory() + "/Documents"
    if requiresCloud && targetCloud != true { throw Failure("icloud_target_not_confirmed") }
}
func validatePlan(_ plan: Plan, journalPath: String) throws {
    guard plan.schema == 1, plan.operations.count <= 200_000,
          validPath(plan.source), validPath(plan.target), validPath(journalPath) else {
        throw Failure("invalid_plan")
    }
    guard !within(plan.target, plan.source) else { throw Failure("target_inside_source") }
    guard !within(journalPath, plan.source), !within(journalPath, plan.target) else {
        throw Failure("journal_must_be_outside_merge_roots")
    }
    guard plan.directories[plan.source] != nil, plan.directories[plan.target] != nil else {
        throw Failure("missing_root_identities")
    }
    let sourceFD = try openDirectory(plan.source, identities: plan.directories)
    defer { close(sourceFD) }
    let targetFD = try openDirectory(plan.target, identities: plan.directories)
    defer { close(targetFD) }
    let sourceDevice = try descriptorStat(sourceFD).st_dev
    guard sourceDevice == (try descriptorStat(targetFD)).st_dev else { throw Failure("cross_volume_merge", EXDEV) }
    try verifyCloudScope(plan)
    for (path, expected) in plan.directories {
        guard validPath(path), fileType(expected.mode) == UInt32(S_IFDIR) else {
            throw Failure("invalid_directory_identity")
        }
    }
    for op in plan.operations {
        guard validPath(op.source), within(op.source, plan.source),
              op.expected.dev == Int64(sourceDevice) else { throw Failure("invalid_operation_source") }
        let kind = fileType(op.expected.mode)
        if kind == UInt32(S_IFLNK) {
            guard op.kind == "move", let link = op.link_target, validPath(link),
                  link != plan.target, within(link, plan.target), !within(link, plan.source),
                  let destination = op.destination, !within(destination, link) else {
                throw Failure("unsafe_symlink_target")
            }
            try verifyLinkReferent(link)
        } else {
            guard kind == UInt32(S_IFREG) || kind == UInt32(S_IFDIR), op.link_target == nil else {
                throw Failure("unsupported_source_type")
            }
        }
        if op.source != plan.source && plan.directories[parent(op.source)] == nil {
            throw Failure("missing_source_parent_identity")
        }
        if op.kind == "move" {
            guard let destination = op.destination, validPath(destination),
                  destination != plan.target, within(destination, plan.target),
                  !within(destination, plan.source), plan.directories[parent(destination)] != nil else {
                throw Failure("invalid_operation_destination")
            }
        } else if op.kind == "rmdir" {
            guard op.destination == nil, kind == UInt32(S_IFDIR) else { throw Failure("invalid_cleanup") }
        } else { throw Failure("unknown_operation") }
    }
}
// Read only the symlink object. Its target is never opened or resolved.
func verifyPlannedLink(_ op: Operation, sourceParent: Int32) throws {
    guard fileType(op.expected.mode) == UInt32(S_IFLNK) else { return }
    var buffer = [UInt8](repeating: 0, count: 65536)
    let count = buffer.withUnsafeMutableBytes {
        readlinkat(sourceParent, leaf(op.source), $0.baseAddress!.assumingMemoryBound(to: CChar.self), $0.count)
    }
    guard count >= 0 else { throw Failure("symlink_read_failed", errno) }
    guard count < buffer.count, let target = String(bytes: buffer.prefix(count), encoding: .utf8),
          target == op.link_target else { throw Failure("symlink_target_changed", ESTALE) }
    try verifyLinkReferent(target)
}
func verifyLinkReferent(_ target: String) throws {
    // The permitted pointer must currently refer to a real file or directory.
    // Walk its parents with O_NOFOLLOW and stat its leaf without following it;
    // dangling targets and chains through other links must never form new cycles.
    do {
        let targetParent = try openDirectory(parent(target))
        defer { close(targetParent) }
        let referent = try entryStat(targetParent, leaf(target))
        let type = fileType(UInt32(referent.st_mode))
        guard type == UInt32(S_IFREG) || type == UInt32(S_IFDIR) else {
            throw Failure("unsafe_symlink_referent", ELOOP)
        }
        try verifyDescriptorPath(targetParent, parent(target))
    } catch {
        throw Failure("unsafe_symlink_referent", (error as? Failure)?.code ?? EINVAL)
    }
}
final class Journal {
    let fd: Int32
    init(_ path: String) throws {
        let directory = try openDirectory(parent(path))
        defer { close(directory) }
        fd = openat(directory, leaf(path), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure("journal_create_failed", errno) }
        guard fchmod(fd, 0o600) == 0 else { close(fd); throw Failure("journal_permissions_failed", errno) }
    }
    deinit { close(fd) }
    func append(_ record: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        data.append(10)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure("journal_write_failed", errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw Failure("journal_sync_failed", errno) }
    }
}
func perform(_ op: Operation, index: Int, plan: Plan, journal: Journal) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    let timeout = DispatchWorkItem { coordinator.cancel() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
    defer { timeout.cancel() }
    var coordinationError: NSError?
    var actionError: Error?
    var entered = false
    let sourceURL = URL(fileURLWithPath: op.source)
    let mutate: (URL, URL?) -> Void = { actualSource, actualDestination in
        entered = true
        do {
            guard actualSource.path == op.source, actualDestination?.path == op.destination else {
                throw Failure("coordinator_redirected_path", ESTALE)
            }
            // Recheck roots, which can be renamed or replaced between coordinated operations.
            let rootFD = try openDirectory(plan.source, identities: plan.directories)
            close(rootFD)
            let targetFD = try openDirectory(plan.target, identities: plan.directories)
            close(targetFD)
            try verifyCloudScope(plan)
            let sourceParent = try openDirectory(parent(op.source), identities: plan.directories)
            defer { close(sourceParent) }
            let observed = try entryStat(sourceParent, leaf(op.source))
            guard fingerprintMatches(observed, op.expected, mutableDirectory: op.kind == "rmdir") else {
                throw Failure("source_changed_since_plan", ESTALE)
            }
            try verifyPlannedLink(op, sourceParent: sourceParent)
            var record: [String: Any] = ["event": "intent", "index": index, "kind": op.kind,
                "source": op.source, "time": ISO8601DateFormatter().string(from: Date())]
            if let destination = op.destination, let destinationURL = actualDestination {
                record["destination"] = destination
                let destinationParent = try openDirectory(parent(destination), identities: plan.directories)
                defer { close(destinationParent) }
                guard observed.st_dev == (try descriptorStat(destinationParent)).st_dev else {
                    throw Failure("cross_volume_move", EXDEV)
                }
                var collision = stat()
                let present = fstatat(destinationParent, leaf(destination), &collision, AT_SYMLINK_NOFOLLOW)
                if present == 0 { throw Failure("destination_exists", EEXIST) }
                guard errno == ENOENT else { throw Failure("destination_stat_failed", errno) }
                try verifyDescriptorPath(sourceParent, parent(op.source))
                try verifyDescriptorPath(destinationParent, parent(destination))
                coordinator.item(at: actualSource, willMoveTo: destinationURL)
                try journal.append(record)
                try verifyDescriptorPath(sourceParent, parent(op.source))
                try verifyDescriptorPath(destinationParent, parent(destination))
                guard fingerprintMatches(try entryStat(sourceParent, leaf(op.source)), op.expected,
                                         mutableDirectory: false) else {
                    throw Failure("source_changed_before_move", ESTALE)
                }
                try verifyPlannedLink(op, sourceParent: sourceParent)
                let result = renameatx_np(sourceParent, leaf(op.source), destinationParent,
                                          leaf(destination), UInt32(RENAME_EXCL))
                let syscallError = result == 0 ? 0 : errno
                defer {
                    if result == 0 { coordinator.item(at: actualSource, didMoveTo: destinationURL) }
                }
                record["event"] = "done"; record["error"] = syscallError
                try journal.append(record)
                guard result == 0 else { throw Failure("exclusive_move_failed", syscallError) }
            } else {
                try verifyDescriptorPath(sourceParent, parent(op.source))
                try journal.append(record)
                try verifyDescriptorPath(sourceParent, parent(op.source))
                guard fingerprintMatches(try entryStat(sourceParent, leaf(op.source)), op.expected,
                                         mutableDirectory: true) else {
                    throw Failure("source_changed_before_cleanup", ESTALE)
                }
                let result = unlinkat(sourceParent, leaf(op.source), AT_REMOVEDIR)
                let syscallError = result == 0 ? 0 : errno
                record["event"] = "done"; record["error"] = syscallError
                try journal.append(record)
                guard result == 0 else { throw Failure("empty_directory_cleanup_failed", syscallError) }
            }
        } catch { actionError = error }
    }
    if let destination = op.destination {
        coordinator.coordinate(writingItemAt: sourceURL,
            options: [.forMoving, .contentIndependentMetadataOnly],
            writingItemAt: URL(fileURLWithPath: destination),
            options: [.forReplacing, .contentIndependentMetadataOnly], error: &coordinationError) {
                mutate($0, $1)
            }
    } else {
        coordinator.coordinate(writingItemAt: sourceURL,
            options: [.forDeleting, .contentIndependentMetadataOnly], error: &coordinationError) {
                mutate($0, nil)
            }
    }
    if let error = actionError { throw error }
    if let error = coordinationError { throw Failure("file_coordination_failed", Int32(clamping: error.code)) }
    guard entered else { throw Failure("file_coordination_cancelled", ECANCELED) }
}

func inspect() {
    while let line = readLine() {
        do {
            guard line.utf8.count <= 1_048_576,
                  let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let paths = object["paths"] as? [String], paths.count <= 2048 else {
                throw Failure("invalid_inspection_request")
            }
            var errors = false
            var packages: [Any] = []
            var ubiquitous: [Any] = []
            for path in paths {
                do {
                    guard validPath(path) else { throw Failure("invalid_path") }
                    let directory = try openDirectory(parent(path))
                    defer { close(directory) }
                    let metadata = try entryStat(directory, leaf(path))
                    guard fileType(UInt32(metadata.st_mode)) != UInt32(S_IFLNK) else {
                        throw Failure("symlink")
                    }
                    let values = try URL(fileURLWithPath: path)
                        .resourceValues(forKeys: [.isPackageKey, .isUbiquitousItemKey])
                    packages.append(values.isPackage.map { $0 as Any } ?? NSNull())
                    ubiquitous.append(values.isUbiquitousItem.map { $0 as Any } ?? NSNull())
                    // A local filesystem may leave ubiquity unset; report null without
                    // invalidating otherwise available package metadata.
                    if values.isPackage == nil { errors = true }
                } catch { errors = true; packages.append(NSNull()); ubiquitous.append(NSNull()) }
            }
            var output: [String: Any] = ["packages": packages, "ubiquitous": ubiquitous]
            if errors { output["error"] = "some_metadata_unavailable" }
            emit(output)
        } catch { emit(["packages": [], "ubiquitous": [], "error": "invalid_inspection_request"]) }
    }
}

// Foundation may log raw provider diagnostics during coordination. Only our
// bounded structured errors are part of this helper's output contract.
let diagnosticsSink = open("/dev/null", O_WRONLY | O_CLOEXEC)
if diagnosticsSink >= 0 { _ = dup2(diagnosticsSink, STDERR_FILENO); close(diagnosticsSink) }
let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "inspect" {
    inspect()
} else if arguments.count == 3 && arguments[1] == "apply" {
    var completed = 0
    var total = 0
    do {
        // Bound memory use; the wrapper sends one frozen plan and closes stdin.
        var bytes = Data()
        while let chunk = try FileHandle.standardInput.read(upToCount: 65536), !chunk.isEmpty {
            bytes.append(chunk)
            guard bytes.count <= 64 * 1024 * 1024 else { throw Failure("plan_too_large", EFBIG) }
        }
        let plan = try JSONDecoder().decode(Plan.self, from: bytes)
        total = plan.operations.count
        try validatePlan(plan, journalPath: arguments[2])
        let journal = try Journal(arguments[2])
        try journal.append(["event": "begin", "schema": 1, "source": plan.source,
                            "target": plan.target, "total": total])
        let deadline = ProcessInfo.processInfo.systemUptime + 300
        for (index, op) in plan.operations.enumerated() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw Failure("overall_deadline_reached", ETIMEDOUT)
            }
            try perform(op, index: index, plan: plan, journal: journal)
            completed += 1
        }
        try journal.append(["event": "complete", "completed": completed, "total": total])
        emit(["ok": true, "completed": completed, "total": total])
    } catch {
        let failure = error as? Failure ?? Failure("invalid_plan_or_io_failure")
        emit(["ok": false, "completed": completed, "total": total,
              "error": failure.message, "error_code": failure.code])
        exit(1)
    }
} else {
    emit(["ok": false, "error": "usage: documents_move inspect | apply NEW_JOURNAL_PATH"])
    exit(2)
}
