import Darwin
import Foundation

/// Reads what is actually running in front of a pty.
///
/// All of this is local kernel state about the user's own processes — the same
/// information `ps` shows. Nothing here reads terminal *contents*.
public enum ProcessInspector {

    /// The foreground process group of a pty, i.e. what has the terminal now.
    public static func foregroundProcessGroup(ofPTY descriptor: Int32) -> pid_t? {
        let group = tcgetpgrp(descriptor)
        return group > 0 ? group : nil
    }

    /// Every pid in a process group.
    public static func processes(inGroup group: pid_t) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, group]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 1)
        guard sysctl(&mib, 4, &entries, &size, nil, 0) == 0 else { return [] }

        return entries.prefix(size / stride).map { $0.kp_proc.p_pid }.filter { $0 > 0 }
    }

    /// The process that best represents a group.
    ///
    /// `npm run dev` spawns node children inside the same group; the group
    /// leader is the command the user actually typed, so prefer it.
    public static func leader(ofGroup group: pid_t) -> pid_t? {
        let members = processes(inGroup: group)
        if members.contains(group) { return group }
        return members.first
    }

    /// `PROC_PIDPATHINFO_MAXSIZE`, which is a macro libproc does not export
    /// to Swift: `4 * MAXPATHLEN`.
    static let maximumPathLength = 4 * Int(MAXPATHLEN)

    /// Absolute path of a process's executable.
    public static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: maximumPathLength)
        let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard written > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    /// Full argv, via `KERN_PROCARGS2`.
    ///
    /// The buffer is laid out as: `argc` (Int32), the exec path, NUL padding,
    /// then `argc` NUL-separated arguments.
    public static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        buffer.removeLast(buffer.count - size)

        let headerSize = MemoryLayout<Int32>.size
        let argc = buffer.prefix(headerSize).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return [] }

        var index = headerSize
        // Skip the exec path, then its NUL padding.
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        var current: [UInt8] = []
        while index < buffer.count, arguments.count < Int(argc) {
            let byte = buffer[index]
            if byte == 0 {
                arguments.append(String(decoding: current, as: UTF8.self))
                current = []
            } else {
                current.append(byte)
            }
            index += 1
        }
        if !current.isEmpty, arguments.count < Int(argc) {
            arguments.append(String(decoding: current, as: UTF8.self))
        }
        return arguments
    }

    /// A process's current working directory.
    public static func workingDirectory(of pid: pid_t) -> URL? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        guard let path = cString(from: info.pvi_cdir.vip_path), path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Interpreters whose own name says nothing about the work being done.
    static let interpreters: Set<String> = [
        "node", "nodejs", "bun", "deno", "python", "python3", "ruby", "perl",
        "php", "java", "sh", "env"
    ]

    /// The name worth showing for a process.
    ///
    /// Agents are often shipped as scripts, so a bare `node` is resolved to the
    /// script it is running — `node .../claude` reads as `claude`.
    public static func logicalName(executablePath: String?, arguments: [String]) -> String? {
        let argv0 = arguments.first ?? executablePath
        guard let argv0 else { return nil }
        let name = basename(argv0)

        guard interpreters.contains(name.lowercased()), arguments.count > 1 else { return name }
        guard let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return name }
        var scriptName = basename(script)
        if let dot = scriptName.lastIndex(of: "."), dot != scriptName.startIndex {
            scriptName = String(scriptName[scriptName.startIndex..<dot])
        }
        return scriptName.isEmpty ? name : scriptName
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Reads a NUL-terminated C char tuple as imported from `libproc`.
    static func cString<T>(from tuple: T) -> String? {
        withUnsafeBytes(of: tuple) { raw -> String? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else { return nil }
            let value = String(cString: base)
            return value.isEmpty ? nil : value
        }
    }
}
