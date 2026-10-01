import Foundation
import RiveRuntime

/// Reads what a `.riv` holds with the Rive runtime: its artboards, each artboard's state machines and their
/// inputs (and the linear animations). The Designer's inspector shows it so a state machine and its inputs are
/// picked from the file instead of typed from memory (issue #33).
///
/// The file is parsed by a `RiveFile` of its own, never one a banner is playing, so reading it cannot disturb a
/// running animation. CDN assets are not fetched (`loadCdn: false`): only names and kinds are wanted.
enum RiveFileInspector {
    /// nil when the file cannot be read, is bigger than an asset may be, or is not a Rive file.
    @MainActor
    static func read(_ url: URL) -> RiveFileInfo? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue, size > 0, size <= AssetStore.maxBytes,
              let data = try? Data(contentsOf: url),
              let file = try? RiveFile(data: data, loadCdn: false) else { return nil }

        var boards: [RiveFileInfo.Artboard] = []
        for name in file.artboardNames() {
            guard let board = try? file.artboard(fromName: name) else { continue }
            var machines: [RiveFileInfo.Machine] = []
            for machineName in board.stateMachineNames() {
                var inputs: [RiveFileInfo.Input] = []
                if let machine = try? board.stateMachine(fromName: machineName) {
                    for inputName in machine.inputNames() {
                        guard let input = try? machine.input(fromName: inputName) else { continue }
                        if input.isTrigger() { inputs.append(.init(name: inputName, kind: .trigger)) }
                        else if input.isBoolean() { inputs.append(.init(name: inputName, kind: .bool)) }
                        else if input.isNumber() { inputs.append(.init(name: inputName, kind: .number)) }
                    }
                }
                machines.append(.init(name: machineName, inputs: inputs))
            }
            boards.append(.init(name: name, width: Double(board.width()), height: Double(board.height()),
                                defaultMachine: board.defaultStateMachine()?.name(),
                                machines: machines, animations: board.animationNames()))
        }
        return boards.isEmpty ? nil : RiveFileInfo(artboards: boards)
    }
}
