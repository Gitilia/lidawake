import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt

/// IOPMrootDomain user-client selector. 1 ignores lid-close sleep. 0 restores it.
/// The bit is sticky: closing the IOKit connection does not clear it.
private let kPMSetClamshellSleepState: UInt32 = 12

private let pidFile: String = {
    let env = ProcessInfo.processInfo.environment["LIDAWAKE_PID_FILE"] ?? ""
    if env.isEmpty {
        return "/tmp/lidawake.pid"
    }
    return env
}()

/// Test hook. When set, the lid state is read from this file ("closed" or "open")
/// instead of IOKit, so the open/close path can run without touching the lid.
private let lidStateFile = ProcessInfo.processInfo.environment["LIDAWAKE_LID_STATE_FILE"] ?? ""

/// Test hook. When set, log display changes instead of making them.
private let skipDisplayChanges = !(ProcessInfo.processInfo.environment["LIDAWAKE_NO_DISPLAY_SLEEP"] ?? "").isEmpty

private var pmConnection: io_connect_t = 0
private var assertionID: IOPMAssertionID = 0

private func fail(_ message: String) -> Never {
    fputs("lidawake: \(message)\n", stderr)
    exit(1)
}

/// `AppleClamshellState` on IOPMrootDomain. True when the lid sensor says closed.
/// nil when the state cannot be read (desktop Mac, or a missing test file).
private func lidClosed() -> Bool? {
    if !lidStateFile.isEmpty {
        guard let text = try? String(contentsOfFile: lidStateFile, encoding: .utf8) else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "closed"
    }
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPMrootDomain")
    )
    guard service != IO_OBJECT_NULL else {
        return nil
    }
    defer { IOObjectRelease(service) }
    guard let raw = IORegistryEntryCreateCFProperty(
        service,
        "AppleClamshellState" as CFString,
        kCFAllocatorDefault,
        0
    ) else {
        return nil
    }
    return (raw.takeRetainedValue() as? Bool) ?? false
}

/// Same request `pmset displaysleepnow` makes. The panel turns off; the system
/// stays awake because of the idle assertion.
private func displayOff() {
    if skipDisplayChanges {
        return
    }
    let pmset = Process()
    pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    pmset.arguments = ["displaysleepnow"]
    pmset.standardOutput = FileHandle.nullDevice
    pmset.standardError = FileHandle.standardError
    do {
        try pmset.run()
        pmset.waitUntilExit()
    } catch {
        fputs("lidawake: could not run pmset displaysleepnow: \(error.localizedDescription)\n", stderr)
    }
}

/// Declaring user activity wakes the display. macOS also does this on lid open;
/// calling it here covers the cases where it does not.
private func displayOn() {
    if skipDisplayChanges {
        return
    }
    var id: IOPMAssertionID = 0
    let status = IOPMAssertionDeclareUserActivity(
        "lidawake lid open" as CFString,
        kIOPMUserActiveLocal,
        &id
    )
    if status == kIOReturnSuccess, id != 0 {
        IOPMAssertionRelease(id)
    }
}

private func setClamshellSleepDisabled(_ disabled: Bool) -> kern_return_t {
    var input: UInt64 = disabled ? 1 : 0
    var outputCount: UInt32 = 0
    return withUnsafePointer(to: &input) { pointer in
        IOConnectCallScalarMethod(
            pmConnection,
            kPMSetClamshellSleepState,
            pointer,
            1,
            nil,
            &outputCount
        )
    }
}

private func openRootDomain() {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPMrootDomain")
    )
    guard service != IO_OBJECT_NULL else {
        fail("IOPMrootDomain not found")
    }
    defer { IOObjectRelease(service) }

    let status = IOServiceOpen(service, mach_task_self_, 0, &pmConnection)
    guard status == KERN_SUCCESS else {
        fail(String(format: "IOServiceOpen failed: 0x%x", status))
    }
}

private func closeRootDomain() {
    if pmConnection != 0 {
        IOServiceClose(pmConnection)
        pmConnection = 0
    }
}

private func holdIdleAssertion() {
    let status = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "lidawake" as CFString,
        &assertionID
    )
    guard status == kIOReturnSuccess else {
        fail(String(format: "idle-sleep assertion failed: 0x%x", status))
    }
}

private func releaseIdleAssertion() {
    if assertionID != 0 {
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}

private func writePIDFile() {
    let body = "\(getpid())\n"
    do {
        try body.write(toFile: pidFile, atomically: true, encoding: .utf8)
    } catch {
        releaseIdleAssertion()
        _ = setClamshellSleepDisabled(false)
        closeRootDomain()
        fail("could not write pid file \(pidFile): \(error.localizedDescription)")
    }
}

private func restoreAndExit() {
    if pmConnection != 0 {
        _ = setClamshellSleepDisabled(false)
    }
    releaseIdleAssertion()
    closeRootDomain()
    unlink(pidFile)
    fputs("lidawake: normal lid sleep restored\n", stderr)
    exit(0)
}

private func clearStickyBit() {
    openRootDomain()
    let status = setClamshellSleepDisabled(false)
    closeRootDomain()
    guard status == KERN_SUCCESS else {
        fail(String(format: "could not restore lid sleep: 0x%x", status))
    }
}

private func runningPID() -> pid_t? {
    guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
          let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
        return nil
    }
    if kill(pid, 0) == 0 {
        return pid
    }
    unlink(pidFile)
    return nil
}

private func commandOff() {
    if let pid = runningPID() {
        kill(pid, SIGTERM)
        for _ in 0..<50 {
            if kill(pid, 0) != 0 { break }
            usleep(100_000)
        }
    }
    clearStickyBit()
    fputs("lidawake: lid sleep is on\n", stderr)
}

private func commandStatus() {
    if let pid = runningPID() {
        print("running \(pid)")
        return
    }
    print("stopped")
}

private func commandOn() {
    if let pid = runningPID() {
        fail("already running (pid \(pid)). Stop it with: lidawake off")
    }

    openRootDomain()
    holdIdleAssertion()

    let status = setClamshellSleepDisabled(true)
    guard status == KERN_SUCCESS else {
        releaseIdleAssertion()
        closeRootDomain()
        fail(String(format: "clamshell override failed: 0x%x", status))
    }

    writePIDFile()

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler { restoreAndExit() }
    interrupt.resume()
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    terminate.setEventHandler { restoreAndExit() }
    terminate.resume()

    var lastLidClosed = lidClosed()
    if lastLidClosed == nil {
        fputs("lidawake: no lid sensor found; the display will stay as it is\n", stderr)
    }

    // Once a second: re-apply the lid flag (plugging or unplugging power can
    // clear it) and react to the lid opening or closing.
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler {
        let again = setClamshellSleepDisabled(true)
        if again != KERN_SUCCESS {
            fputs(String(format: "lidawake: re-apply failed: 0x%x\n", again), stderr)
        }

        guard let closed = lidClosed() else {
            return
        }
        if closed == lastLidClosed {
            return
        }
        lastLidClosed = closed
        if closed {
            fputs("lidawake: lid closed, display off\n", stderr)
            displayOff()
        } else {
            fputs("lidawake: lid open, display on\n", stderr)
            displayOn()
        }
    }
    timer.resume()

    fputs(
        """
        lidawake: clamshell override on
        The Mac stays awake with the lid closed.
        The display turns off when the lid closes and comes back when it opens.
        Ctrl-C, or `lidawake off` in another terminal, turns normal sleep back on.
        kill -9 does not. Run `lidawake off` if that happens, or reboot.
        Leave the Mac on a desk. A closed lid still gets warm, so do not put it in a bag.

        """,
        stderr
    )
    dispatchMain()
}

switch CommandLine.arguments.dropFirst().first {
case nil, "on":
    commandOn()
case "off":
    commandOff()
case "status":
    commandStatus()
default:
    fputs("usage: lidawake [on|off|status]\n", stderr)
    exit(2)
}
