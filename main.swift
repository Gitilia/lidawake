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

private var pmConnection: io_connect_t = 0
private var assertionID: IOPMAssertionID = 0

private func fail(_ message: String) -> Never {
    fputs("lidawake: \(message)\n", stderr)
    exit(1)
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

    // Plugging or unplugging power can clear the bit. Re-apply while we run.
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 2, repeating: 2)
    timer.setEventHandler {
        let again = setClamshellSleepDisabled(true)
        if again != KERN_SUCCESS {
            fputs(String(format: "lidawake: re-apply failed: 0x%x\n", again), stderr)
        }
    }
    timer.resume()

    fputs(
        """
        lidawake: clamshell override on
        The Mac stays awake with the lid closed.
        Ctrl-C, or `lidawake off` in another terminal, turns normal sleep back on.
        kill -9 does not. Run `lidawake off` if that happens, or reboot.
        Leave the Mac on a desk. A closed lid gets hot, so do not put it in a bag.

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
