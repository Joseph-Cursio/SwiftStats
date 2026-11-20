//
//  InterruptCleanup.swift
//  SwiftStatsCore
//
//  What `swiftstats` does on SIGINT, SIGTERM or SIGHUP: it terminates the
//  tools it started and removes its temporary files (`ScratchRegistry`),
//  then ends as the signal would have ended it, so its exit status is
//  unchanged (128 plus the signal's number in a shell). A signal the
//  process started with ignored, as `nohup` leaves SIGHUP and a shell
//  leaves SIGINT for a background job, stays ignored.
//

import Foundation

/// Cleans up when a command is interrupted.
public enum InterruptCleanup {
    /// The signals that end a command and are cleaned up after.
    static let signals = [SIGINT, SIGTERM, SIGHUP]

    /// Installs the handlers; call once, before any work starts.
    public static func install() {
        install(registry: .shared, signals: signals)
    }

    /// Installs handlers that clean up `registry` and end the process on
    /// each of `signals`.
    static func install(registry: ScratchRegistry, signals: [Int32]) {
        let queue = DispatchQueue(label: "SwiftStats.InterruptCleanup")
        // A dispatch source hears a signal even while it is ignored, so an
        // ignored one gets none.
        for number in signals where isIgnored(number) == false {
            // A handler that does nothing, rather than SIG_IGN: the source
            // below still hears the signal, the process no longer ends at
            // once, and a child starts with the default action, where an
            // ignored signal would stay ignored across exec.
            signal(number) { _ in
                // The dispatch source handles it.
            }
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                registry.end(by: number)
            }
            source.resume()
            registry.keep(source)
        }
    }

    /// Whether signal `number` is ignored now.
    static func isIgnored(_ number: Int32) -> Bool {
        var action = sigaction()
        guard sigaction(number, nil, &action) == 0 else {
            return false
        }
        let handler = unsafeBitCast(action.__sigaction_u.__sa_handler, to: OpaquePointer?.self)
        return handler == unsafeBitCast(SIG_IGN, to: OpaquePointer?.self)
    }
}
