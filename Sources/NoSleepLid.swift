// NoSleepLid — keep your Mac awake with the lid closed, from the menu bar.
//
// Left click the icon: turn on / pause. Right click: menu.
// On:  `pmset disablesleep 1` + `caffeinate -d` (tied to the app's PID), and the
//      built-in screen and keyboard backlight go to brightness 0 while the lid is shut.
// Off: everything is undone. Quitting, `kill`/`pkill` (SIGTERM/SIGHUP) also undo it,
//      and a crashed session is repaired the next time the app starts.
// Safety: turns itself off below 15% battery; the log only records state changes,
//         is capped at 1 MB and stops writing when less than 2 GB of disk is free.

import AppKit
import IOKit
import IOKit.ps
import ServiceManagement

// MARK: - Config

let batteryFloor = 15
let logMaxBytes: UInt64 = 1_000_000
let logMinFreeBytes: Int64 = 2_000_000_000
let keyboardID: UInt64 = 1
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/NoSleepLid.log")

// MARK: - Log

func log(_ msg: String) {
    let fm = FileManager.default
    if let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()),
       let free = attrs[.systemFreeSize] as? Int64, free < logMinFreeBytes { return }
    if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? UInt64, size > logMaxBytes {
        let old = logURL.appendingPathExtension("1")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: logURL, to: old)
    }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date()))  \(msg)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: false, encoding: .utf8)
    }
}

// MARK: - Hardware

enum Hardware {
    static func lidClosed() -> Bool {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(svc) }
        let v = IORegistryEntryCreateCFProperty(svc, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (v?.takeRetainedValue() as? Bool) ?? false
    }

    /// (percent, on battery?) — nil on Macs without a battery.
    static func battery() -> (Int, Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            return (cur * 100 / max, onBattery)
        }
        return nil
    }

    // Built-in screen — DisplayServices (private framework)
    private typealias GetB = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetB = @convention(c) (UInt32, Float) -> Int32
    private static let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getB: GetB? = dlsym(ds, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetB.self) }
    private static let setB: SetB? = dlsym(ds, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetB.self) }

    static var screen: Float? {
        get { var b: Float = -1; guard getB?(CGMainDisplayID(), &b) == 0 else { return nil }; return b }
        set { if let v = newValue { _ = setB?(CGMainDisplayID(), v) } }
    }

    // Keyboard backlight — KeyboardBrightnessClient (CoreBrightness, private framework)
    private static let kbc: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    static var keyboard: Float? {
        get {
            guard let c = kbc else { return nil }
            let sel = NSSelectorFromString("brightnessForKeyboard:")
            typealias F = @convention(c) (AnyObject, Selector, UInt64) -> Float
            return unsafeBitCast(c.method(for: sel), to: F.self)(c, sel, keyboardID)
        }
        set {
            guard let c = kbc, let v = newValue else { return }
            let sel = NSSelectorFromString("setBrightness:forKeyboard:")
            typealias F = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
            _ = unsafeBitCast(c.method(for: sel), to: F.self)(c, sel, v, keyboardID)
        }
    }
}

// MARK: - pmset

enum Sleep {
    static func isDisabled() -> Bool {
        run("/usr/bin/pmset", ["-g"]).range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    /// Uses the sudoers rule (no password); if `interactive`, falls back to the admin prompt.
    @discardableResult
    static func setDisabled(_ on: Bool, interactive: Bool) -> Bool {
        let arg = on ? "1" : "0"
        if runStatus("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", arg]) == 0 { return true }
        guard interactive else { return false }
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(arg)\" with administrator privileges"
        return runStatus("/usr/bin/osascript", ["-e", script]) == 0
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    static func runStatus(_ path: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit(); return p.terminationStatus
    }
}

func notify(_ text: String) {
    let safe = text.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "'")
    _ = Sleep.runStatus("/usr/bin/osascript", ["-e", "display notification \"\(safe)\" with title \"NoSleepLid\""])
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var caffeinate: Process?
    private var timer: Timer?
    private var active = false
    private var lidWasClosed = false
    private var savedScreen: Float = 1.0
    private var savedKeyboard: Float = 1.0
    private var warning: String?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        // Recovery: a previous session died and left "never sleep" on.
        if Sleep.isDisabled() {
            if Sleep.setDisabled(false, interactive: false) {
                log("recovery: SleepDisabled was 1 with no active session -> 0")
            } else {
                warning = "SleepDisabled = 1 (sudoers rule missing?)"
                log("recovery failed: could not reset SleepDisabled without a password")
            }
        }
        // kill/pkill (SIGTERM, SIGHUP) skip applicationWillTerminate:
        // catch them and quit through the normal path, which pauses first.
        for sig in [SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshIcon()
        log("app started")
    }

    func applicationWillTerminate(_ n: Notification) {
        if active { deactivate(reason: "app quit") }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    @objc private func toggle() { active ? deactivate(reason: "paused by user") : activate() }

    private func activate() {
        if let (pct, onBatt) = Hardware.battery(), onBatt, pct < batteryFloor {
            notify("Battery at \(pct)%. Plug in the charger to turn it on.")
            return
        }
        guard Sleep.setDisabled(true, interactive: true) else {
            notify("Could not disable sleep (permission denied)."); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-d", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        try? p.run()
        caffeinate = p
        savedScreen = Hardware.screen.flatMap { $0 > 0 ? $0 : nil } ?? 1.0
        savedKeyboard = Hardware.keyboard.flatMap { $0 > 0 ? $0 : nil } ?? 1.0
        lidWasClosed = Hardware.lidClosed()
        active = true
        warning = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        log("ON (screen=\(savedScreen), keyboard=\(savedKeyboard))")
        refreshIcon()
    }

    private func deactivate(reason: String) {
        timer?.invalidate(); timer = nil
        caffeinate?.terminate(); caffeinate = nil
        if lidWasClosed || Hardware.screen == 0 { restoreBrightness() }
        if !Sleep.setDisabled(false, interactive: true) {
            warning = "SleepDisabled stuck at 1 — run: sudo pmset -a disablesleep 0"
            notify("Could not re-enable sleep. See the menu.")
        }
        active = false
        lidWasClosed = false
        log("OFF (\(reason))")
        refreshIcon()
    }

    private func tick() {
        if let (pct, onBatt) = Hardware.battery(), onBatt, pct < batteryFloor {
            deactivate(reason: "battery at \(pct)%")
            notify("Battery at \(pct)% — NoSleepLid turned off, your Mac can sleep now.")
            return
        }
        let closed = Hardware.lidClosed()
        if closed != lidWasClosed {
            if closed {
                if let s = Hardware.screen, s > 0 { savedScreen = s }
                if let k = Hardware.keyboard, k > 0 { savedKeyboard = k }
                Hardware.screen = 0
                Hardware.keyboard = 0
                log("lid closed -> brightness 0 (will restore screen=\(savedScreen), keyboard=\(savedKeyboard))")
            } else {
                restoreBrightness()
                log("lid opened -> brightness restored")
            }
            lidWasClosed = closed
        } else if closed {
            Hardware.keyboard = 0   // in the dark, auto-brightness tries to light the keyboard again
        }
    }

    private func restoreBrightness() {
        Hardware.screen = savedScreen
        Hardware.keyboard = savedKeyboard
    }

    private func refreshIcon() {
        let name = warning != nil ? "exclamationmark.triangle" : (active ? "cup.and.saucer.fill" : "moon.zzz")
        let img = NSImage(systemSymbolName: name, accessibilityDescription: active ? "On" : "Off")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = active ? "NoSleepLid: on (Mac will not sleep)" : "NoSleepLid: off"
    }

    private func showMenu() {
        let m = NSMenu()
        m.addItem(withTitle: active ? "Pause (let the Mac sleep)" : "Turn on (stay awake with lid closed)",
                  action: #selector(toggle), keyEquivalent: "").target = self
        m.addItem(.separator())
        var status = active ? "Status: on" : "Status: off"
        if let (pct, onBatt) = Hardware.battery() { status += " · battery \(pct)%\(onBatt ? "" : " ⚡︎")" }
        m.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        m.addItem(withTitle: "Turns off below \(batteryFloor)% on battery", action: nil, keyEquivalent: "").isEnabled = false
        if let w = warning { m.addItem(withTitle: "⚠︎ \(w)", action: nil, keyEquivalent: "").isEnabled = false }
        m.addItem(.separator())
        let login = m.addItem(withTitle: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(withTitle: "Open log", action: #selector(openLog), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { notify("Could not change open at login: \(error.localizedDescription)") }
    }

    @objc private func openLog() { NSWorkspace.shared.open(logURL) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
