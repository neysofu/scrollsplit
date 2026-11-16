import AppKit
import SwiftUI
import ApplicationServices
import ServiceManagement

enum ScrollDevice: String {
    case mouse = "Mouse wheel"
    case trackpad = "Trackpad / smooth scroll"

    static func classify(_ event: CGEvent) -> ScrollDevice {
        event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 ? .mouse : .trackpad
    }
}

enum ScrollTransform {
    static let vertical: [CGEventField] = [
        .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventAcceleratedDeltaAxis1, .scrollWheelEventRawDeltaAxis1
    ]

    static func apply(_ event: CGEvent, enabled: Bool, mouse: Bool, trackpad: Bool) {
        guard enabled, ScrollDevice.classify(event) == .mouse ? mouse : trackpad else { return }
        // Snapshot every representation before mutating the event.
        let values = vertical.map { event.getIntegerValueField($0) }
        for (field, value) in zip(vertical, values) {
            event.setIntegerValueField(field, value: value == Int64.min ? Int64.max : -value)
        }
    }
}

final class ScrollController: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var reverseMouse: Bool { didSet { defaults.set(reverseMouse, forKey: "reverseMouse") } }
    @Published var reverseTrackpad: Bool { didSet { defaults.set(reverseTrackpad, forKey: "reverseTrackpad") } }
    @Published var ready = false
    @Published var permissionGranted = false
    @Published var lastDevice = "Waiting for scrolling…"
    @Published var loginEnabled = false
    @Published var loginMessage: String?
    private let defaults = UserDefaults.standard
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    init() {
        defaults.register(defaults: ["enabled": true, "reverseMouse": true, "reverseTrackpad": false])
        enabled = defaults.bool(forKey: "enabled")
        reverseMouse = defaults.bool(forKey: "reverseMouse")
        reverseTrackpad = defaults.bool(forKey: "reverseTrackpad")
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        permissionGranted = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
        guard permissionGranted else { stopTap(); return }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            ready = CGEvent.tapIsEnabled(tap: tap)
            return
        }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<ScrollController>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
            let detected = ScrollDevice.classify(event).rawValue
            if controller.lastDevice != detected { controller.lastDevice = detected }
            ScrollTransform.apply(event, enabled: controller.enabled,
                                  mouse: controller.reverseMouse, trackpad: controller.reverseTrackpad)
            return Unmanaged.passUnretained(event)
        }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
                callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            ready = false
            return
        }
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            return
        }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        ready = true
    }

    func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        ready = false
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibility()
    }

    func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func toggleLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = SMAppService.mainApp.status == .requiresApproval
                ? "Approve ScrollSplit in System Settings → General → Login Items." : nil
        } catch { loginMessage = error.localizedDescription }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var controller: ScrollController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScrollSplit").font(.system(size: 19, weight: .semibold))
                    Text("Two devices. Your directions.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 7) {
                Circle().fill(controller.ready ? (controller.enabled ? Color.green : Color.orange) : Color.orange)
                    .frame(width: 7, height: 7)
                Text(controller.ready ? (controller.enabled ? "Active" : "Paused") :
                    (controller.permissionGranted ? "Unable to start · try quitting and reopening" : "Accessibility access needed"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !controller.ready {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Allow ScrollSplit to adjust scrolling in other apps. Enable it in System Settings → Privacy & Security → Accessibility.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button(controller.permissionGranted ? "Open Accessibility Settings" : "Grant Accessibility Access") {
                        controller.requestAccess()
                    }.buttonStyle(.borderedProminent)
                    Text("If it isn’t listed, use + and choose this ScrollSplit app. It will connect automatically after approval.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            Toggle("Enable ScrollSplit", isOn: $controller.enabled).toggleStyle(.switch)
            Divider()
            VStack(spacing: 16) {
                deviceRow("Mouse", detail: "Wheel scrolling", icon: "computermouse", binding: $controller.reverseMouse)
                deviceRow("Trackpad", detail: "Touch and smooth scrolling", icon: "rectangle.and.hand.point.up.left", binding: $controller.reverseTrackpad)
            }.disabled(!controller.enabled)

            Text("Reverse vertical scrolling relative to your macOS setting. Horizontal scrolling stays the same.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: "waveform.path")
                Text(controller.lastDevice)
            }.font(.caption).foregroundStyle(.secondary)

            DisclosureGroup("About device detection") {
                Text("Mouse wheels usually send line-based scrolling; trackpads send continuous scrolling. Magic Mouse and some smooth-scrolling mouse drivers can also report continuous scrolling and use the Trackpad switch. Test each device with this panel open to see its detected type.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            }.font(.caption)
            Divider()
            Toggle("Open at login", isOn: Binding(get: { controller.loginEnabled }, set: { controller.toggleLogin($0) }))
                .toggleStyle(.switch).controlSize(.small)
            if let message = controller.loginMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Vertical only · On this Mac").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(20).frame(width: 360)
    }

    func deviceRow(_ title: String, detail: String, icon: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 23)).frame(width: 30).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Reverse vertical scrolling for \(title)", isOn: binding).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SettingsPanel: View {
    @ObservedObject var controller: ScrollController
    let size: NSSize

    var body: some View {
        ScrollView(.vertical) {
            SettingsView(controller: controller)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: size.width, height: size.height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = ScrollController()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var hostingController: NSHostingController<SettingsPanel>!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.scrollsplit.app")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApplication.shared.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "ScrollSplit")
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "ScrollSplit — mouse & trackpad scrolling"
        }
        popover.behavior = .transient
        popover.animates = false
        hostingController = NSHostingController(rootView: SettingsPanel(controller: controller, size: NSSize(width: 360, height: 580)))
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController
        controller.start()
        if !controller.ready || CommandLine.arguments.contains("--check-layout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.togglePopover()
                if CommandLine.arguments.contains("--check-layout") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard let window = self.hostingController.view.window, let screen = window.screen else {
                            fatalError("Popover did not open")
                        }
                        let frame = window.frame
                        let visible = screen.visibleFrame
                        print("Layout: popover \(frame), visible screen \(visible)")
                        fflush(stdout)
                        precondition(visible.contains(frame), "Popover outside visible screen: \(frame), screen: \(visible)")
                        print("PASS: popover \(frame) fits visible screen \(visible)")
                        fflush(stdout)
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func woke() { controller.stopTap(); controller.refresh() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return true
    }
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            controller.refresh()
            // Size against the status item's display, which can change in clamshell mode.
            let screen = button.window?.screen ?? NSScreen.main
            let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil))
            let availableHeight = min(visibleFrame.maxY, anchor?.minY ?? visibleFrame.maxY) - visibleFrame.minY - 24
            let size = NSSize(width: 360, height: max(120, min(580, availableHeight)))
            hostingController.rootView = SettingsPanel(controller: controller, size: size)
            hostingController.view.setFrameSize(size)
            hostingController.preferredContentSize = size
            popover.contentSize = size
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            confinePopover(to: visibleFrame)
            DispatchQueue.main.async { self.confinePopover(to: visibleFrame) }
        }
    }
    func confinePopover(to visibleFrame: NSRect) {
        guard let window = hostingController.view.window else { return }
        let frame = window.frame
        let x = max(visibleFrame.minX + 4, min(frame.minX, visibleFrame.maxX - frame.width - 4))
        let y = max(visibleFrame.minY + 4, min(frame.minY, visibleFrame.maxY - frame.height - 4))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func applicationWillTerminate(_ notification: Notification) { controller.stopTap() }
}

func runSelfTests() {
    var count = 0
    for continuous in [false, true] {
        for enabled in [false, true] {
            for mouse in [false, true] {
                for trackpad in [false, true] {
                    for direction: Int32 in [-7, 0, 7] {
                        let event = CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line,
                                            wheelCount: 2, wheel1: direction, wheel2: 3, wheel3: 0)!
                        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
                        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
                        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
                        event.flags = [.maskShift]
                        let before = ScrollTransform.vertical.map { event.getIntegerValueField($0) }
                        let horizontal: [CGEventField] = [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2,
                                                        .scrollWheelEventFixedPtDeltaAxis2]
                        let beforeHorizontal = horizontal.map { event.getIntegerValueField($0) }
                        ScrollTransform.apply(event, enabled: enabled, mouse: mouse, trackpad: trackpad)
                        let reversed = enabled && (continuous ? trackpad : mouse)
                        precondition(ScrollTransform.vertical.map { event.getIntegerValueField($0) } == before.map { reversed ? -$0 : $0 })
                        precondition(horizontal.map { event.getIntegerValueField($0) } == beforeHorizontal)
                        precondition(event.flags == [.maskShift])
                        precondition(event.getIntegerValueField(.scrollWheelEventScrollPhase) == 2)
                        precondition(event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 1)
                        precondition(ScrollDevice.classify(event) == (continuous ? .trackpad : .mouse))
                        count += 1
                    }
                }
            }
        }
    }
    print("Passed \(count) scroll transformation cases: direction, device selection, pause, horizontal deltas, phases, modifiers.")
}

if CommandLine.arguments.contains("--self-test") {
    runSelfTests()
} else {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
