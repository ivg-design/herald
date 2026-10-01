import SwiftUI
import AppKit

/// `image`: fills the width of its cell. Height comes from `height`, else from the aspect ratio (explicit,
/// else the picture's own), so the row it sits in is as tall as the picture needs.
struct ImageComponentView: View {
    let component: HeraldImageComponent
    let ctx: GridContext

    private static let idealSide: CGFloat = 48

    var body: some View {
        let img = ctx.image(forBinding: component.binding)
        let remote = ctx.remoteImageURL(forBinding: component.binding)
        let ratio = ratio(for: img)
        let shape = RoundedRectangle(cornerRadius: component.cornerRadius, style: .continuous)
        frameBox(ratio: ratio)
            .overlay {
                if let img {
                    pic(Image(nsImage: img))
                } else if let remote {
                    AsyncImage(url: remote) { phase in
                        if let i = phase.image { pic(i) } else { Color.clear }
                    }
                }
            }
            .clipShape(shape)
            .contentShape(shape)
    }

    private func ratio(for img: NSImage?) -> CGFloat {
        if let r = component.aspectRatio, r > 0 { return CGFloat(r) }
        if let img, img.size.width > 0, img.size.height > 0 { return img.size.width / img.size.height }
        return 1
    }

    /// An invisible box with the cell width and the picture's height; a kept empty image is just this.
    @ViewBuilder private func frameBox(ratio: CGFloat) -> some View {
        if let h = component.height, h > 0 {
            Color.clear.frame(idealWidth: CGFloat(h) * ratio, idealHeight: CGFloat(h)).frame(height: CGFloat(h))
        } else {
            Color.clear
                .frame(idealWidth: Self.idealSide, idealHeight: Self.idealSide / ratio)
                .aspectRatio(ratio, contentMode: .fit)
        }
    }

    @ViewBuilder private func pic(_ image: Image) -> some View {
        switch component.fit {
        case .cover: image.resizable().scaledToFill()
        case .fit: image.resizable().scaledToFit()
        case .fill: image.resizable()
        }
    }
}
