#if DEBUG
import SwiftUI
import AppKit

/// The status item's menu drawn as a view: a real NSMenu cannot be captured without opening it on screen. The rows come from the
/// app's own menu (`AppDelegate.menuNeedsUpdate`), so titles, shortcuts and checkmarks are the real ones.
struct ShotMenuView: View {
    struct Row: Identifiable { let id = UUID(); var title: String; var key: String; var separator: Bool; var checked: Bool; var submenu: Bool; var enabled: Bool }
    let rows: [Row]

    init(menu: NSMenu) {
        rows = menu.items.map { i in
            var key = ""
            if !i.keyEquivalent.isEmpty { key = "\u{2318}" + i.keyEquivalent.uppercased() }
            return Row(title: i.title, key: key, separator: i.isSeparatorItem, checked: i.state == .on, submenu: i.submenu != nil, enabled: i.isEnabled)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { r in
                if r.separator { Divider().padding(.vertical, 4).padding(.horizontal, 10) }
                else {
                    HStack(spacing: 6) {
                        Text(r.checked ? "\u{2713}" : "").frame(width: 12)
                        Text(r.title).foregroundStyle(r.enabled ? Color.primary : Color.secondary)
                        Spacer(minLength: 24)
                        Text(r.submenu ? "\u{203A}" : r.key).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 22)
                }
            }
        }
        .padding(.vertical, 6).frame(width: 270)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}
#endif
