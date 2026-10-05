#if DEBUG
import AppKit
import HeraldClient
import RiveRuntime

/// Proof that a `.riv` really moves inside Herald's own Rive component, without showing anything on a display.
///
/// ```sh
/// HERALD_RIVE_PROBE=/path/to/file.riv HERALD_RIVE_PROBE_OUT=/tmp/probe HERALD_SUPPORT_DIR=/tmp/sandbox Herald
/// ```
///
/// The component is put in a window far outside the displays, or with HERALD_RIVE_PROBE_ONSCREEN=1 in a fully
/// transparent window on a display (an animation only ticks on a display). Every 0.4 s for about ten seconds it is
/// captured and the number of different frames is written to stderr, with the frames as PNGs in the output directory. Nothing else of the app starts; the process exits when it is done.
/// HERALD_RIVE_PROBE_NUMBER (a view-model number path such as `eyes/X-axis`) also prints that value at each step.
/// HERALD_RIVE_PROBE_ARTBOARD and HERALD_RIVE_PROBE_MACHINE pick an artboard and a state machine.
@MainActor
enum RiveProbe {
    private static var window: NSWindow?

    static func runIfAsked() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["HERALD_RIVE_PROBE"], !path.isEmpty else { return false }
        let out = URL(fileURLWithPath: env["HERALD_RIVE_PROBE_OUT"] ?? NSTemporaryDirectory() + "herald-rive-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var component = HeraldRiveComponent()
        component.path = path
        component.artboard = env["HERALD_RIVE_PROBE_ARTBOARD"]
        component.stateMachine = env["HERALD_RIVE_PROBE_MACHINE"]
        let host = RiveHostView(frame: NSRect(x: 0, y: 0, width: 240, height: 240))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.backgroundColor = .white
        w.contentView = host
        if env["HERALD_RIVE_PROBE_ONSCREEN"] == "1" {
            // On a display so the display link ticks, but fully transparent, never key and deaf to the mouse.
            w.alphaValue = 0; w.ignoresMouseEvents = true; w.level = .normal
            w.setFrameOrigin(NSPoint(x: 40, y: 40)); w.orderFrontRegardless()
        } else { _ = ShotKit.place(w) }
        window = w
        host.apply(RiveHostView.Config(component: component, app: "probe", manifest: nil, fields: [:], assets: .shared))

        Task { @MainActor in
            var hashes: [Int] = []
            var samples: [String] = []
            let numberPath = ProcessInfo.processInfo.environment["HERALD_RIVE_PROBE_NUMBER"]
            for i in 0..<25 {
                if ProcessInfo.processInfo.environment["HERALD_RIVE_PROBE_MANUAL"] == "1" { for _ in 0..<24 { _ = host.viewModel?.riveModel?.stateMachine?.advance(by: 1.0 / 60.0); host.viewModel?.riveModel?.artboard?.advance(by: 1.0 / 60.0) } }
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let numberPath, let v = host.boundInstance?.numberProperty(fromPath: numberPath)?.value { samples.append(String(format: "%.2f", v)) }
                if let numberPath, let inst = host.dataBoundInstance, let v = try? await inst.value(of: NumberProperty(path: numberPath)) { samples.append(String(format: "%.2f", v)) }
                guard let grab = await ShotKit.grab(w, name: "probe-\(i)"), let bytes = ShotKit.rgba(grab.image) else { continue }
                hashes.append(bytes.hashValue)
                if let png = ShotKit.png(grab.image) { try? png.write(to: out.appendingPathComponent(String(format: "frame-%02d.png", i))) }
            }
            let line = "rive-probe: frames=\(hashes.count) distinct=\(Set(hashes).count) dataBound=\(host.playsDataBound) bound=\(host.boundInstance != nil) error=\(host.loadError ?? "none")\n"
            FileHandle.standardError.write(Data(line.utf8))
            if !samples.isEmpty { FileHandle.standardError.write(Data(("rive-probe: " + (numberPath ?? "") + " = " + samples.joined(separator: " ") + "\n").utf8)) }
            exit(0)
        }
        return true
    }
}
#endif
