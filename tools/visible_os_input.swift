// Dormant macOS OS-input instrument. No launch, activation, permission request,
// Unicode substitution, event tap, pointer warp or game-internal input API.
// Default/preflight/plan branches never create or post an input event.
import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import Carbon
import CryptoKit
import Darwin
import Dispatch

let armPhrase = "POST-TO-VERIFIED-FOREGROUND"
let physicalKeys: [String: CGKeyCode] = [
    "w": CGKeyCode(kVK_ANSI_W), "a": CGKeyCode(kVK_ANSI_A),
    "s": CGKeyCode(kVK_ANSI_S), "d": CGKeyCode(kVK_ANSI_D),
    "space": CGKeyCode(kVK_Space), "escape": CGKeyCode(kVK_Escape)
]
let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate,
                                 .maskCommand, .maskAlphaShift, .maskSecondaryFn]

struct Refusal: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func hexDigest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

func fileDigest(_ path: String) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let length = attributes[.size] as? NSNumber,
          length.uint64Value <= 64 * 1024 * 1024 else {
        throw Refusal("executable exceeds 64 MiB hash budget")
    }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    var hash = SHA256()
    var total = 0
    while let part = try handle.read(upToCount: 65536), !part.isEmpty {
        total += part.count
        guard total <= 64 * 1024 * 1024 else {
            throw Refusal("executable grew beyond hash budget")
        }
        hash.update(data: part)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

func property(_ source: TISInputSource, _ key: CFString) -> CFTypeRef? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
}

struct KeyboardIdentity {
    let inputID: String
    let layoutID: String
    let report: [String: Any]
}

func keyboardIdentity() -> KeyboardIdentity {
    let input = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let layout = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    func describe(_ source: TISInputSource) -> [String: Any] {
        var result: [String: Any] = [
            "id": property(source, kTISPropertyInputSourceID) as? String ?? "",
            "name": property(source, kTISPropertyLocalizedName) as? String ?? ""
        ]
        if let data = property(source, kTISPropertyUnicodeKeyLayoutData) as? Data {
            result["unicode_layout_bytes"] = data.count
            result["unicode_layout_sha256"] = hexDigest(data)
        }
        return result
    }
    let inputReport = describe(input)
    let layoutReport = describe(layout)
    return KeyboardIdentity(inputID: inputReport["id"] as? String ?? "",
                            layoutID: layoutReport["id"] as? String ?? "",
                            report: ["input_source": inputReport,
                                     "layout_source": layoutReport,
                                     "key_names_mean": "ANSI physical positions; layout determines characters",
                                     "unicode_text_override": false])
}

func foregroundPID() -> pid_t? {
    NSWorkspace.shared.frontmostApplication?.processIdentifier
}

func preflight() -> [String: Any] {
    let front = NSWorkspace.shared.frontmostApplication
    return [
        "mode": "preflight", "helper_pid": getpid(), "parent_pid": getppid(),
        "post_event_access": CGPreflightPostEventAccess(),
        "accessibility_trusted": AXIsProcessTrusted(),
        "foreground_pid": front.map { Int($0.processIdentifier) } as Any? ?? NSNull(),
        "foreground_bundle_id": front?.bundleIdentifier as Any? ?? NSNull(),
        "keyboard": keyboardIdentity().report,
        "physical_keys": physicalKeys.mapValues { Int($0) },
        "hid_modifier_flags": CGEventSource.flagsState(.hidSystemState).rawValue,
        "hid_key_down": physicalKeys.mapValues {
            CGEventSource.keyState(.hidSystemState, key: $0)
        },
        "permission_requests": 0, "event_objects_created": 0, "post_attempts": 0,
        "delivery_verified": false
    ]
}

enum Operation {
    case hold(keys: [String], durationMS: Int)
    case relative(dx: Int, dy: Int, moves: Int, intervalMS: Int)

    var plan: [String: Any] {
        switch self {
        case let .hold(keys, duration):
            return ["operation": "hold", "keys": keys,
                    "virtual_key_codes": keys.map { Int(physicalKeys[$0]!) },
                    "duration_ms": duration, "planned_post_attempts": keys.count * 2,
                    "auto_repeat": false]
        case let .relative(dx, dy, moves, interval):
            return ["operation": "relative", "delta_x": dx, "delta_y": dy,
                    "moves": moves, "interval_ms": interval,
                    "planned_post_attempts": moves,
                    "mouse_type": "mouseMoved", "position_policy": "fixed current global cursor position",
                    "relative_delivery_verified": false]
        }
    }
}

struct ExpectedTarget {
    let pid: pid_t
    let path: String
    let sha256: String
    let inputID: String
    let layoutID: String
}

struct Arguments {
    let mode: String
    let operation: Operation?
    let target: ExpectedTarget?

    static func parse(_ arguments: [String]) throws -> Arguments {
        let switches: Set<String> = ["--preflight", "--plan", "--help"]
        let values: Set<String> = ["--arm", "--operation", "--keys", "--duration-ms",
            "--dx", "--dy", "--moves", "--interval-ms", "--target-pid",
            "--target-executable", "--target-sha256", "--expect-input-source",
            "--expect-layout-source"]
        var fields: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard fields[key] == nil else { throw Refusal("duplicate option: \(key)") }
            if switches.contains(key) {
                fields[key] = ""
                index += 1
            } else if values.contains(key) {
                guard index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw Refusal("missing value: \(key)")
                }
                fields[key] = arguments[index + 1]
                index += 2
            } else {
                throw Refusal("unknown option: \(key)")
            }
        }
        let modes = ["--preflight", "--plan", "--help", "--arm"].filter { fields[$0] != nil }
        guard modes.count <= 1 else { throw Refusal("select exactly one mode") }
        let mode = modes.first ?? "--preflight"
        if mode == "--preflight" || mode == "--help" {
            guard fields.keys.allSatisfy({ $0 == mode }) else {
                throw Refusal("preflight/help admit no operation or target options")
            }
            return Arguments(mode: mode, operation: nil, target: nil)
        }
        if mode == "--arm", fields["--arm"] != armPhrase {
            throw Refusal("explicit arm phrase does not match")
        }
        func integer(_ key: String, _ range: ClosedRange<Int>) throws -> Int {
            guard let text = fields[key], let value = Int(text), range.contains(value),
                  String(value) == text else { throw Refusal("invalid or missing \(key)") }
            return value
        }
        let operation: Operation
        let operationKeys: Set<String>
        switch fields["--operation"] {
        case "hold":
            let keys = (fields["--keys"] ?? "").split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard (1...2).contains(keys.count), Set(keys).count == keys.count,
                  keys.allSatisfy({ physicalKeys[$0] != nil }) else {
                throw Refusal("hold requires 1 or 2 distinct keys from w,a,s,d,space,escape")
            }
            operation = .hold(keys: keys, durationMS: try integer("--duration-ms", 20...2000))
            operationKeys = ["--keys", "--duration-ms"]
        case "relative":
            let dx = try integer("--dx", -64...64)
            let dy = try integer("--dy", -64...64)
            guard dx != 0 || dy != 0 else { throw Refusal("relative delta must be nonzero") }
            operation = .relative(dx: dx, dy: dy, moves: try integer("--moves", 2...8),
                                  intervalMS: try integer("--interval-ms", 20...200))
            operationKeys = ["--dx", "--dy", "--moves", "--interval-ms"]
        default: throw Refusal("operation must be hold or relative")
        }
        let targetKeys: Set<String> = ["--target-pid", "--target-executable", "--target-sha256",
                                      "--expect-input-source", "--expect-layout-source"]
        let admitted = operationKeys.union(targetKeys).union([mode, "--operation"])
        guard fields.keys.allSatisfy({ admitted.contains($0) }) else {
            throw Refusal("option belongs to a different operation")
        }
        let target: ExpectedTarget?
        if fields.keys.contains(where: { targetKeys.contains($0) }) || mode == "--arm" {
            let pid = try integer("--target-pid", 2...Int(Int32.max))
            guard let path = fields["--target-executable"], path.hasPrefix("/"),
                  let digest = fields["--target-sha256"], digest.count == 64,
                  digest.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let inputID = fields["--expect-input-source"], !inputID.isEmpty,
                  let layoutID = fields["--expect-layout-source"], !layoutID.isEmpty else {
                throw Refusal("target requires absolute executable, lowercase SHA256, input/layout IDs")
            }
            guard pid != Int(getpid()), pid != Int(getppid()) else {
                throw Refusal("helper and parent cannot be the target")
            }
            target = ExpectedTarget(pid: pid_t(pid), path: path, sha256: digest,
                                    inputID: inputID, layoutID: layoutID)
        } else { target = nil }
        return Arguments(mode: mode, operation: operation, target: target)
    }
}

struct FileIdentity: Equatable {
    let inode: UInt64
    let device: UInt64
    let size: UInt64
    let modified: Date
    init(_ path: String) throws {
        let data = try FileManager.default.attributesOfItem(atPath: path)
        guard data[.type] as? FileAttributeType == .typeRegular,
              let inode = data[.systemFileNumber] as? NSNumber,
              let device = data[.systemNumber] as? NSNumber,
              let size = data[.size] as? NSNumber,
              let modified = data[.modificationDate] as? Date else {
            throw Refusal("target is not an identifiable regular executable")
        }
        self.inode = inode.uint64Value; self.device = device.uint64Value
        self.size = size.uint64Value; self.modified = modified
    }
}

struct BoundTarget {
    let expected: ExpectedTarget
    let path: String
    let launchDate: Date
    let file: FileIdentity

    init(_ expected: ExpectedTarget) throws {
        let path = URL(fileURLWithPath: expected.path).standardizedFileURL.resolvingSymlinksInPath().path
        guard let app = NSRunningApplication(processIdentifier: expected.pid), !app.isTerminated,
              let actual = app.executableURL?.resolvingSymlinksInPath().path,
              actual == path, let date = app.launchDate else {
            throw Refusal("target PID/executable/launch identity does not match")
        }
        let file = try FileIdentity(path)
        guard try fileDigest(path) == expected.sha256,
              try FileIdentity(path) == file else { throw Refusal("target executable SHA256 changed or differs") }
        self.expected = expected; self.path = path; self.launchDate = date; self.file = file
    }

    func processIdentityGuard() throws {
        guard let app = NSRunningApplication(processIdentifier: expected.pid), !app.isTerminated,
              app.launchDate == launchDate,
              app.executableURL?.resolvingSymlinksInPath().path == path else {
            throw Refusal("target process identity changed or exited")
        }
    }

    func identityGuard(hash: Bool = false) throws {
        try processIdentityGuard()
        guard try FileIdentity(path) == file else { throw Refusal("target executable file identity changed") }
        if hash, try fileDigest(path) != expected.sha256 { throw Refusal("target executable digest changed") }
    }

    func foregroundGuard(hash: Bool = false) throws {
        try identityGuard(hash: hash)
        guard CGPreflightPostEventAccess() else { throw Refusal("post-event permission absent or revoked") }
        guard foregroundPID() == expected.pid else { throw Refusal("target lost foreground") }
        let keyboard = keyboardIdentity()
        guard keyboard.inputID == expected.inputID, keyboard.layoutID == expected.layoutID else {
            throw Refusal("keyboard input/layout source changed")
        }
        guard CGEventSource.flagsState(.hidSystemState).intersection(modifierMask).isEmpty else {
            throw Refusal("physical modifier or caps-lock active")
        }
    }

    var report: [String: Any] {
        ["pid": Int(expected.pid), "executable": path, "sha256": expected.sha256,
         "launch_time": launchDate.timeIntervalSince1970, "inode": file.inode,
         "device": file.device, "bytes": file.size,
         "input_source_id": expected.inputID, "layout_source_id": expected.layoutID]
    }
}

// Signal handlers only request cancellation. Input cleanup runs in the main
// operation's defer, outside a POSIX signal handler. SIGKILL cannot be handled.
final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var received: Int32?
    func request(_ number: Int32) { lock.lock(); received = received ?? number; lock.unlock() }
    func check() throws {
        lock.lock(); let number = received; lock.unlock()
        if let number { throw Refusal("signal \(number)") }
    }
}

final class Instrument {
    let target: BoundTarget
    let cancellation = Cancellation()
    let started = ProcessInfo.processInfo.systemUptime
    var traces: [[String: Any]] = []
    var held: [(name: String, code: CGKeyCode, up: CGEvent)] = []
    var signals: [DispatchSourceSignal] = []
    var cleanupReason = "completed"

    init(_ target: BoundTarget) {
        self.target = target
        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            let cancellation = self.cancellation
            source.setEventHandler { cancellation.request(number) }
            source.resume()
            signals.append(source)
        }
    }

    func guardNormal(hash: Bool = false) throws {
        try cancellation.check()
        guard ProcessInfo.processInfo.systemUptime - started <= 5 else {
            throw Refusal("operation exceeded 5-second total budget")
        }
        try target.foregroundGuard(hash: hash)
    }

    func trace(_ fields: [String: Any]) {
        var item = fields
        item["elapsed_ms"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
        item["target_pid"] = Int(target.expected.pid)
        item["foreground_pid"] = foregroundPID().map { Int($0) } as Any? ?? NSNull()
        traces.append(item)
    }

    func wait(_ milliseconds: Int) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + Double(milliseconds) / 1000
        repeat {
            try guardNormal()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { break }
            Thread.sleep(forTimeInterval: min(0.01, remaining))
        } while true
    }

    func cleanup() {
        // Cleanup never retargets to the foreground application. Revalidate PID
        // identity first. A lost-foreground keyUp is intentional and recorded;
        // it cannot prove the client's own focus-triggered release behavior.
        for key in held.reversed() {
            do {
                // A changed on-disk executable must abort normal input, but
                // must not suppress keyUp to the still-original live process.
                try target.processIdentityGuard()
                key.up.timestamp = DispatchTime.now().uptimeNanoseconds
                key.up.postToPid(target.expected.pid)
                trace(["event": "keyUp", "key": key.name, "virtual_key": Int(key.code),
                       "phase": "cleanup", "reason": cleanupReason,
                       "result": "post_attempted_delivery_unverified",
                       "post_event_access_at_cleanup": CGPreflightPostEventAccess()])
            } catch {
                trace(["event": "keyUp", "key": key.name, "phase": "cleanup",
                       "result": "not_posted_identity_refusal", "reason": String(describing: error)])
            }
        }
        held.removeAll()
        for source in signals { source.cancel() }
    }

    func run(_ operation: Operation) throws {
        defer { cleanup() }
        do {
            try guardNormal(hash: true)
            switch operation {
            case let .hold(keys, duration):
                guard keys.allSatisfy({ !CGEventSource.keyState(.hidSystemState, key: physicalKeys[$0]!) }) else {
                    throw Refusal("requested physical key is already held")
                }
                // Prepare all matching ups before the first down. Allocation
                // failure therefore cannot leave a down without a cleanup up.
                var prepared: [(String, CGKeyCode, CGEvent, CGEvent)] = []
                for name in keys {
                    let code = physicalKeys[name]!
                    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
                          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
                        throw Refusal("keyboard event allocation failed")
                    }
                    down.flags = []; up.flags = []
                    down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                    up.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                    prepared.append((name, code, down, up))
                }
                for (name, code, down, up) in prepared {
                    try guardNormal(hash: true)
                    // Register cleanup before the void posting call.
                    held.append((name, code, up))
                    down.timestamp = DispatchTime.now().uptimeNanoseconds
                    down.postToPid(target.expected.pid)
                    trace(["event": "keyDown", "key": name, "virtual_key": Int(code),
                           "phase": "operation", "result": "post_attempted_delivery_unverified"])
                }
                try wait(duration)
                // Even successful release uses the single cleanup path.
            case let .relative(dx, dy, moves, interval):
                guard let cursor = CGEvent(source: nil)?.location else {
                    throw Refusal("cannot read current cursor position")
                }
                for index in 0..<moves {
                    try guardNormal(hash: true)
                    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                              mouseCursorPosition: cursor, mouseButton: .left) else {
                        throw Refusal("mouse event allocation failed")
                    }
                    event.flags = []
                    event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
                    event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
                    // Constructors and hashing precede a fresh foreground check.
                    try guardNormal()
                    event.timestamp = DispatchTime.now().uptimeNanoseconds
                    event.postToPid(target.expected.pid)
                    trace(["event": "mouseMoved", "phase": "operation", "index": index,
                           "delta_x": dx, "delta_y": dy, "position_x": cursor.x, "position_y": cursor.y,
                           "result": "post_attempted_relative_delivery_unverified"])
                    if index + 1 < moves { try wait(interval) }
                }
            }
        } catch {
            cleanupReason = String(describing: error)
            throw error
        }
    }
}

func emit(_ value: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    } catch {
        FileHandle.standardError.write(Data("JSON trace serialization failed\n".utf8))
    }
}

var report: [String: Any] = ["schema": "visible-os-input-v1", "post_attempts": 0,
                            "permission_requests": 0, "delivery_verified": false]
var status: Int32 = 0
do {
    let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    if arguments.mode == "--help" {
        report["mode"] = "help"
        report["read_only"] = ["default or --preflight", "--plan --operation hold --keys w --duration-ms 300",
                               "--plan --operation relative --dx 12 --dy -4 --moves 2 --interval-ms 60"]
        report["arm_requires"] = ["--arm \(armPhrase)", "--target-pid PID",
            "--target-executable ABSOLUTE_PATH", "--target-sha256 LOWERCASE_HEX64",
            "--expect-input-source ID", "--expect-layout-source ID", "operation options"]
    } else if arguments.mode == "--preflight" {
        report.merge(preflight()) { _, latest in latest }
        report["status"] = "read_only_complete"
    } else if arguments.mode == "--plan" {
        report.merge(preflight()) { _, latest in latest }
        report["mode"] = "plan"
        report["plan"] = arguments.operation!.plan
        if let expected = arguments.target {
            do {
                let target = try BoundTarget(expected)
                report["target"] = target.report
                try target.foregroundGuard(hash: true)
                report["armed_guard_if_checked_now"] = "would_pass_access_identity_foreground_layout"
            } catch { report["armed_guard_if_checked_now"] = String(describing: error) }
        } else { report["armed_guard_if_checked_now"] = "not_checked_no_target" }
        report["status"] = "read_only_plan_complete"
    } else {
        // The only branch that can instantiate Instrument or create/post events.
        let target = try BoundTarget(arguments.target!)
        try target.foregroundGuard(hash: true)
        report["mode"] = "armed"
        report["target"] = target.report
        report["plan"] = arguments.operation!.plan
        let instrument = Instrument(target)
        do {
            try instrument.run(arguments.operation!)
            report["status"] = "post_attempts_complete_delivery_unverified"
        } catch {
            status = 1
            report["status"] = "aborted_cleanup_attempted"
            report["error"] = String(describing: error)
        }
        report["trace"] = instrument.traces
        report["post_attempts"] = instrument.traces.filter {
            ($0["result"] as? String)?.hasPrefix("post_attempted") == true
        }.count
        report["elapsed_ms"] = (ProcessInfo.processInfo.systemUptime - instrument.started) * 1000
        report["cleanup_boundary"] = "matching keyUp attempted on completed/handled abort; target exit/reuse, SIGKILL, crash, or permission revocation may prevent delivery"
    }
} catch {
    status = 1
    report["status"] = "refused_before_post"
    report["error"] = String(describing: error)
}
emit(report)
exit(status)
