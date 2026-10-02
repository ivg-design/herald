import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Image component's Source (issue #61): the issuer's own picture, a fixed one chosen here, or another image
/// field. All three are just the component's `binding`: `{image}`, a path inside Herald's support folder, `{key}`.
struct ImageSourceControl: View {
    @ObservedObject var model: DesignerModel
    @Binding var binding: String
    @State private var problem: String?

    static let issuerTitle = "From issuer \u{00B7} {image} (the image the sending app attached)"
    static let fixedTitle = "Fixed image\u{2026} (choose a file; overrides the issuer\u{2019}s; stored in the app\u{2019}s support folder)"
    static let fieldTitle = "Field\u{2026} (another image field from the manifest)"

    private var choice: ImageSourceChoice { ImageSourceChoice.classify(binding) }

    /// Fields of type image the manifest declares, other than the standard `{image}`; plus any other image-typed
    /// token the Designer knows about.
    private var imageFields: [TokenSuggestion] {
        model.tokenSuggestions.filter { ($0.type == .image || model.tokenType($0.key) == .image) && $0.key != "image" }
    }

    private var current: String {
        switch choice {
        case .issuer: return "From issuer \u{00B7} {image}"
        case .fixed(let p): return "Fixed image \u{00B7} \((p as NSString).lastPathComponent)"
        case .field(let k): return "Field \u{00B7} {\(k)}"
        case .custom: return "Custom binding"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldRow("Source") {
                Menu {
                    Button(Self.issuerTitle) { binding = ImageSourceChoice.issuerBinding }
                    Button(Self.fixedTitle) { chooseFile() }
                    Menu(Self.fieldTitle) {
                        if imageFields.isEmpty {
                            Text("The manifest declares no other image field")
                        } else {
                            ForEach(imageFields) { f in
                                Button { binding = f.token } label: {
                                    if let s = f.sampleText { Text("\(f.token)   \(s)") } else { Text(f.token) }
                                }
                            }
                        }
                    }
                } label: { Text(current).lineLimit(1) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            switch choice {
            case .issuer:
                Text("The image the sending app attached to the notification. Nothing is drawn when it sends none.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .fixed(let path):
                fixedDetail(path)
            case .field(let key):
                Text("The value of {\(key)}, an image field of the \(model.issuerName) manifest.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .custom:
                FieldRow("Binding") { TokenTextField(model: model, title: "{image}", text: $binding) }
            }
            if let problem {
                Text(problem).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func fixedDetail(_ path: String) -> some View {
        let expanded = (path as NSString).expandingTildeInPath
        let image = NSImage(contentsOfFile: expanded)
        HStack(spacing: 8) {
            if let image {
                Image(nsImage: image).resizable().scaledToFill().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "photo.badge.exclamationmark").frame(width: 40, height: 40).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(image == nil ? "The file is missing" : (TemplateImageStore.shared.contains(path) ? "Kept in Herald\u{2019}s support folder" : "Used from where it is"))
                    .font(.caption2).foregroundStyle(image == nil ? .orange : .secondary)
            }
            Spacer(minLength: 0)
            Button("Choose\u{2026}") { chooseFile() }.controlSize(.small)
        }
        Text("The same picture for every notification; it overrides the issuer\u{2019}s image.")
            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Fixed Image"
        panel.message = "Choose the picture this template always shows. Herald keeps a copy in its support folder."
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let stored = try TemplateImageStore.shared.install(url, app: model.draft.app)
            problem = nil
            binding = stored.path
        } catch {
            problem = error.localizedDescription
        }
    }
}
