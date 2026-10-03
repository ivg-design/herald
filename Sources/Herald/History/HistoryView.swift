import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Publishes a tick whenever Herald data changes so SwiftUI views re-read the stores.
@MainActor
final class ChangeTicker: ObservableObject {
    @Published var tick = 0
    private var obs: NSObjectProtocol?
    init() {
        obs = NotificationCenter.default.addObserver(forName: .heraldChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick += 1 }
        }
    }
    deinit { if let obs { NotificationCenter.default.removeObserver(obs) } }
}

/// History window: apps sidebar with counts, search, newest-first list of banner-style rows.
struct HistoryView: View {
    let controller: AppController
    @StateObject private var ticker = ChangeTicker()
    /// The sidebar's selection, tagged by `HistorySelection.id`: "All Apps" (the default on open) or an app id. (Optional so the
    /// sidebar List can bind it directly.)
    @State private var selection: String? = HistorySelection.all.id
    @State private var search = ""
    @State private var picked = Set<HistoryKey>()
    @State private var confirmClearApp: String?
    /// Groups (`HistoryGrouping`) the user has opened; the rest show one row.
    @State private var openGroups = Set<String>()
    @FocusState private var searchFocused: Bool

    private var browser: HistoryBrowser { HistoryBrowser(selection: HistorySelection(id: selection), search: search) }
    private var appFilter: String? { browser.selection.app }

    private var apps: [String] { _ = ticker.tick; return controller.history.apps() }

    private func displayName(_ app: String) -> String { controller.registry.displayName(for: app) }

    private var items: [HeraldHistoryItem] {
        _ = ticker.tick
        return browser.items(history: controller.history) { displayName($0) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detail
        }
        .frame(minWidth: 680, minHeight: 400)
        .confirmationDialog("Clear all history for \(confirmClearApp.map(displayName) ?? "this app")?",
                            isPresented: Binding(get: { confirmClearApp != nil }, set: { if !$0 { confirmClearApp = nil } }),
                            titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                if let a = confirmClearApp { controller.clearHistory(app: a); picked.removeAll() }
                confirmClearApp = nil
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        _ = ticker.tick   // re-read the stores whenever Herald data changes
        return List(selection: $selection) {
            // "All Apps" is a row like the others (same ForEach, same tag type), so it selects the same way.
            ForEach(browser.rows(history: controller.history) { displayName($0) }) { row in
                sidebarRow(row)
                    .tag(row.id as String?)
                    .contextMenu {
                        if let app = row.selection.app {
                            Button("Export JSON\u{2026}") { export(controller.history.items(app: app), name: app) }
                            Button("Clear \(displayName(app)) History", role: .destructive) { confirmClearApp = app }
                        } else {
                            Button("Export JSON\u{2026}") { export(controller.history.allItems(), name: "all-apps") }
                        }
                    }
            }
        }
        .onChange(of: selection) { _ in picked.removeAll() }
        .onChange(of: apps) { _ in
            var b = browser
            b.reconcile(history: controller.history)   // the selected app is gone (deleted): back to All Apps
            if b.selection.id != selection { selection = b.selection.id }
        }
    }

    @ViewBuilder private func sidebarRow(_ row: HistoryBrowser.Row) -> some View {
        HStack(spacing: 8) {
            if let app = row.selection.app {
                Image(nsImage: AppIcons.icon(in: controller.registry, app: app)).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "tray.full").frame(width: 18, height: 18)
            }
            Text(row.title).lineLimit(1)
            Spacer(minLength: 4)
            if row.unread > 0 {
                Text("\(row.unread)").font(.caption2.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                    .help("\(row.unread) not dismissed")
            }
            Text("\(row.total)").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Detail

    private var detail: some View {
        let shown = items
        return VStack(spacing: 0) {
            searchBar(count: shown.count)
            Divider()
            if shown.isEmpty {
                emptyState
            } else {
                List(selection: $picked) {
                    // Notifications of one app that share a `group` (DESIGN section 9) fold under one disclosure row.
                    ForEach(HistoryGrouping.rows(shown)) { row in
                        switch row {
                        case .item(let item):
                            historyRow(item)
                        case .group(let g):
                            groupHeader(g)
                            if openGroups.contains(g.id) {
                                ForEach(g.items) { item in historyRow(item).padding(.leading, 20) }
                            }
                        }
                    }
                }
                // Backspace / forward-delete on the selection (macOS "Delete" key).
                .onDeleteCommand { delete(picked.isEmpty ? [] : shown.filter { picked.contains(HistoryKey($0)) }) }
            }
        }
    }

    private func historyRow(_ item: HeraldHistoryItem) -> some View {
        HistoryRow(item: item, appName: displayName(item.app),
                   icon: AppIcons.icon(in: controller.registry, app: item.app))
            .tag(HistoryKey(item))
            // simultaneous so the click still selects the row while also opening its url.
            .simultaneousGesture(TapGesture().onEnded { open(item) })
            .contextMenu { menu(for: item) }
    }

    /// The row of a group: its name, how many notifications it holds and how many are not dismissed. A click opens it.
    private func groupHeader(_ g: HistoryGrouping.Group) -> some View {
        let isOpen = openGroups.contains(g.id)
        return HStack(spacing: 8) {
            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 12)
            Image(nsImage: AppIcons.icon(in: controller.registry, app: g.app))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(g.group).font(.headline).lineLimit(1)
                Text("\(displayName(g.app)) \u{00B7} \(g.items.count) notifications" + (g.unread > 0 ? " \u{00B7} \(g.unread) not dismissed" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if isOpen { openGroups.remove(g.id) } else { openGroups.insert(g.id) } }
        .contextMenu {
            if g.unread > 0 {
                Button("Dismiss \(g.unread) Not Dismissed") {
                    for t in g.items where t.dismissedAt == nil { controller.dismissItem(app: t.app, id: t.id, action: nil, notify: false) }
                    controller.changed()
                }
            }
            Button("Delete Group", role: .destructive) { delete(g.items) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(g.group), \(g.items.count) notifications, \(isOpen ? "expanded" : "collapsed")")
    }

    private func searchBar(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search title, subtitle, body, app", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { if search.isEmpty { searchFocused = false } else { search = "" } } .heraldHelp(.historySearch)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).heraldHelp(.historyClearSearch)
            }
            Text("\(count) item\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            Menu {
                Button("Export JSON\u{2026}") { export(items, name: appFilter ?? "all-apps") }
                    .disabled(items.isEmpty)
                if let a = appFilter {
                    Divider()
                    Button("Clear \(displayName(a)) History\u{2026}", role: .destructive) { confirmClearApp = a }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize() .heraldHelp(.historyMore)
            // Hidden button purely to own the Cmd-F shortcut.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "bell.slash" : "magnifyingglass")
                .font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(search.isEmpty
                 ? (appFilter == nil ? "No notifications yet" : "No notifications from \(displayName(appFilter!)) yet")
                 : "No matches for \u{201C}\(search)\u{201D}")
                .font(.headline).foregroundStyle(.secondary)
            if search.isEmpty {
                Text("Apps send notifications to Herald over its local API; they show up here.")
                    .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            } else {
                Button("Clear Search") { search = "" } .heraldHelp(.historyClearSearch)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    @ViewBuilder
    private func menu(for item: HeraldHistoryItem) -> some View {
        // Right-clicking an unselected row acts on that row; on a selected row it acts on the whole selection.
        let targets = picked.contains(HistoryKey(item)) && picked.count > 1
            ? items.filter { picked.contains(HistoryKey($0)) } : [item]
        if targets.count == 1 {
            if url(of: item) != nil { Button("Open") { open(item, dismiss: false) } }
            Button("Re-show as Banner") { reshow(item) }
            if item.dismissedAt == nil { Button("Dismiss") { controller.dismissItem(app: item.app, id: item.id, action: nil) } }
        } else {
            Button("Dismiss \(targets.count) Items") {
                for t in targets where t.dismissedAt == nil { controller.dismissItem(app: t.app, id: t.id, action: nil) }
            }
        }
        Button(targets.count == 1 ? "Delete" : "Delete \(targets.count) Items", role: .destructive) { delete(targets) }
        Divider()
        Button("Clear \(displayName(item.app)) History\u{2026}", role: .destructive) { confirmClearApp = item.app }
        Button("Export JSON\u{2026}") { export(targets, name: targets.count == 1 ? item.id : displayName(item.app)) }
    }

    private func url(of item: HeraldHistoryItem) -> URL? {
        item.notification.url.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// A click acts like clicking the banner: opens the url (or focuses the app) and, if the banner is
    /// still up, dismisses it. Already-dismissed items just open their url so the recorded action isn't overwritten.
    private func open(_ item: HeraldHistoryItem, dismiss: Bool = true) {
        if item.dismissedAt == nil && dismiss {
            controller.userOpened(app: item.app, id: item.id)
        } else if let u = url(of: item), !AppController.openSafely(u) {
            NSSound.beep()   // not a web or mail link, or nothing can open it
        }
    }

    /// Sends the stored notification back through the normal delivery path (new banner, sound, fresh
    /// delivery time) instead of reimplementing banner presentation here.
    private func reshow(_ item: HeraldHistoryItem) {
        let n = item.notification
        Task { @MainActor in _ = try? await controller.notify(n) }
    }

    private func delete(_ targets: [HeraldHistoryItem]) {
        guard !targets.isEmpty else { return }
        for t in targets { controller.dismissItem(app: t.app, id: t.id, action: nil, notify: false) } // closes a live banner; one refresh below
        HistoryBrowser.delete(targets, from: controller.history)
        picked.subtract(targets.map(HistoryKey.init))
        controller.changed()
    }

    private func export(_ items: [HeraldHistoryItem], name: String) {
        guard !items.isEmpty else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "herald-history-\(name).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try HistorySearch.exportJSON(items).write(to: url, options: .atomic) }
        catch {
            let a = NSAlert(error: error)
            a.runModal()
        }
    }
}
