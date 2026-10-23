import Darwin

enum ProcessArgs {
    /// `pid` followed by its parent, grandparent, ... up to (not including) launchd.
    static func ancestry(of pid: pid_t) -> [Int32] {
        var chain: [Int32] = []
        var p = pid
        while p > 1 && chain.count < 64 && !chain.contains(p) {
            chain.append(p)
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { break }
            p = info.kp_eproc.e_ppid
        }
        return chain
    }

    /// The command line of a same-user process (argv joined by spaces), via `KERN_PROCARGS2`.
    static func commandLine(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return nil }
        // Layout: argc (Int32), exec path, NUL padding, argv[0..argc), environment.
        let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }
        while i < size && buf[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < argc && i < size {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args.joined(separator: " ")
    }
}
