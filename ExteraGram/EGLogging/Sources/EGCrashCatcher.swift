import Foundation
import UIKit

private let crashReportKey = "eg_crash_report"
private let crashReportFile = "eg_last_crash.txt"

private func crashFilePath() -> String {
    let tmp = NSTemporaryDirectory()
    return tmp + crashReportFile
}

// MARK: - Signal handler (async-signal-safe)

private var crashSignals: [Int32] = [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
private var previousHandlers: [Int32: sig_t] = [:]

private func signalHandler(_ signal: Int32) {
    var info = ""
    switch signal {
    case SIGSEGV:  info = "SIGSEGV (Segmentation fault)"
    case SIGABRT:  info = "SIGABRT (Abort)"
    case SIGBUS:   info = "SIGBUS (Bus error)"
    case SIGILL:   info = "SIGILL (Illegal instruction)"
    case SIGFPE:   info = "SIGFPE (Floating point exception)"
    case SIGTRAP:  info = "SIGTRAP (Trap)"
    default:       info = "Signal \(signal)"
    }

    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
    let count = backtrace(&frames, 64)
    let symbols = backtrace_symbols(&frames, count)

    var report = "=== ExteraGram Crash Report ===\n"
    report += "Signal: \(info)\n"
    report += "Date: \(Date())\n\n"
    report += "Backtrace:\n"

    if let symbols = symbols {
        for i in 0..<Int(count) {
            if let sym = symbols[i] {
                report += String(cString: sym) + "\n"
            }
        }
        free(symbols)
    }

    // Write to file (sync, no malloc after this point in real signal handler)
    let path = crashFilePath()
    report.withCString { ptr in
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 {
            write(fd, ptr, strlen(ptr))
            close(fd)
        }
    }

    // Re-raise to get default behavior
    if let prev = previousHandlers[signal], prev != SIG_DFL && prev != SIG_IGN {
        prev(signal)
    } else {
        var sa = sigaction()
        sa.__sigaction_u = unsafeBitCast(SIG_DFL, to: __sigaction_u.self)
        sigaction(signal, &sa, nil)
        raise(signal)
    }
}

// MARK: - ObjC exception handler

private func uncaughtExceptionHandler(_ exception: NSException) {
    var report = "=== ExteraGram Crash Report ===\n"
    report += "Exception: \(exception.name.rawValue)\n"
    report += "Reason: \(exception.reason ?? "nil")\n"
    report += "Date: \(Date())\n\n"
    report += "Call Stack:\n"
    report += exception.callStackSymbols.joined(separator: "\n")

    let path = crashFilePath()
    try? report.write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: - Public API

public class EGCrashCatcher {

    public static func install() {
        // Register ObjC exception handler
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)

        // Register signal handlers
        for sig in crashSignals {
            var sa = sigaction()
            let handler: @convention(c) (Int32) -> Void = signalHandler
            sa.__sigaction_u = unsafeBitCast(handler, to: __sigaction_u.self)
            sa.sa_flags = Int32(SA_NODEFER)
            var old = sigaction()
            sigaction(sig, &sa, &old)
            previousHandlers[sig] = old.__sigaction_u.__sa_handler
        }
    }

    /// Call on every launch — if a crash report exists, copies it to clipboard and shows alert
    public static func checkAndReport(in window: UIWindow?) {
        let path = crashFilePath()
        guard FileManager.default.fileExists(atPath: path),
              let report = try? String(contentsOfFile: path, encoding: .utf8),
              !report.isEmpty else { return }

        // Remove file so we don't show it again
        try? FileManager.default.removeItem(atPath: path)

        // Copy to clipboard
        UIPasteboard.general.string = report

        // Show alert
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "ExteraGram Crash Detected",
                message: "Crash report copied to clipboard.\n\nFirst lines:\n" + report.prefix(300),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            window?.rootViewController?.present(alert, animated: true)
        }
    }
}
