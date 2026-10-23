import Darwin
import FociCore
import Foundation
import os

/// Wire protocol: the client sends its arguments as one JSON array line; the server answers with one
/// `CLIResponse` JSON line and closes. For `subscribe` the server keeps the connection and writes one
/// `StatusDTO` JSON line per change.
public enum CLISocket {
    public static var path: String { URL.applicationSupportDirectory.appending(path: "Foci/foci.sock").path }

    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
        }
        return addr
    }

    static func withAddress<T>(_ addr: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var a = addr
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }
}

/// Runs inside the app.
@MainActor
public final class CLIServer {
    private let log = Logger(subsystem: "dev.foci", category: "cli")
    private let path: String
    private let handler: () -> CLIHandler?
    private var listenSource: DispatchSourceRead?
    private var readers: [Int32: (source: DispatchSourceRead, buffer: Data)] = [:]
    private var subscribers: Set<Int32> = []
    private var lastStatus: Data?

    public init(path: String = CLISocket.path, handler: @escaping () -> CLIHandler?) {
        self.path = path
        self.handler = handler
    }

    public func start() {
        signal(SIGPIPE, SIG_IGN)  // a client that went away must not kill the app
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, let addr = CLISocket.address(path),
            CLISocket.withAddress(addr, { bind(fd, $0, $1) }) == 0, listen(fd, 16) == 0
        else {
            log.error("can't listen on \(self.path, privacy: .public): \(String(cString: strerror(errno)), privacy: .public)")
            if fd >= 0 { close(fd) }
            return
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.accept(fd) } }
        source.setCancelHandler { close(fd) }
        source.resume()
        listenSource = source
    }

    public func stop() {
        listenSource?.cancel()
        for (fd, r) in readers {
            r.source.cancel()
            close(fd)
        }
        for fd in subscribers { close(fd) }
        readers = [:]
        subscribers = []
        unlink(path)
    }

    /// Sends the status to subscribers if it changed.
    public func publish(_ status: StatusDTO) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // stable bytes, so unchanged status is detected
        guard !subscribers.isEmpty, var line = try? encoder.encode(status), line != lastStatus else { return }
        lastStatus = line
        line.append(0x0A)
        for fd in subscribers where !CLISocket.writeAll(fd, line) {
            subscribers.remove(fd)
            close(fd)
        }
    }

    private func accept(_ listenFD: Int32) {
        while true {
            let fd = Darwin.accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.read(fd) } }
            readers[fd] = (source, Data())
            source.resume()
        }
    }

    private func read(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &chunk, chunk.count)
        guard n > 0 else {
            finish(fd, keepOpen: false)
            return
        }
        readers[fd]?.buffer.append(contentsOf: chunk[0..<n])
        guard let buffer = readers[fd]?.buffer, let newline = buffer.firstIndex(of: 0x0A) else { return }

        let request: CLIRequest
        do {
            let args = try JSONDecoder().decode([String].self, from: buffer[..<newline])
            request = try CLIRequest.parse(args)
        } catch {
            respond(fd, CLIResponse(exitCode: 2, stderr: "\(error)\n"))
            return
        }
        if request == .subscribe {
            finish(fd, keepOpen: true)
            subscribers.insert(fd)
            lastStatus = nil  // the new subscriber gets the current status right away
            if let status = handler()?.status() { publish(status) }
            return
        }
        guard let handler = handler() else {
            respond(fd, CLIResponse(exitCode: 3, stderr: "foci is waiting for the Accessibility permission\n"))
            return
        }
        respond(fd, handler.handle(request))
    }

    private func respond(_ fd: Int32, _ response: CLIResponse) {
        if var data = try? JSONEncoder().encode(response) {
            data.append(0x0A)
            _ = fcntl(fd, F_SETFL, 0)  // blocking: responses are small, and the client is waiting
            _ = CLISocket.writeAll(fd, data)
        }
        finish(fd, keepOpen: false)
    }

    /// Stops reading from the connection. The read source's cancel handler doesn't close the fd,
    /// so subscribers stay writable.
    private func finish(_ fd: Int32, keepOpen: Bool) {
        readers.removeValue(forKey: fd)?.source.cancel()
        if !keepOpen { close(fd) }
    }
}

/// Runs in the `foci <args>` process.
public enum CLIClient {
    public static func run(_ args: [String], path: String = CLISocket.path) -> Int32 {
        let request: CLIRequest
        do {
            request = try CLIRequest.parse(args)
        } catch {
            FileHandle.standardError.write(Data("foci: \(error)\n\nrun 'foci help' for usage\n".utf8))
            return 2
        }
        if request == .help {
            print(CLIRequest.usage)
            return 0
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, let addr = CLISocket.address(path), CLISocket.withAddress(addr, { connect(fd, $0, $1) }) == 0
        else {
            FileHandle.standardError.write(Data("foci: the Foci app is not running\n".utf8))
            return 3
        }
        defer { close(fd) }
        var line = (try? JSONEncoder().encode(args)) ?? Data("[]".utf8)
        line.append(0x0A)
        guard CLISocket.writeAll(fd, line) else { return 3 }

        if request == .subscribe {
            // Stream lines until the app quits.
            setvbuf(stdout, nil, _IOLBF, 0)
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(fd, &chunk, chunk.count)
                if n <= 0 { return 0 }
                fwrite(chunk, 1, n, stdout)
            }
        }

        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            data.append(contentsOf: chunk[0..<n])
        }
        guard let response = try? JSONDecoder().decode(CLIResponse.self, from: data) else {
            FileHandle.standardError.write(Data("foci: no response from the app\n".utf8))
            return 3
        }
        FileHandle.standardOutput.write(Data(response.stdout.utf8))
        FileHandle.standardError.write(Data(response.stderr.utf8))
        return response.exitCode
    }
}
