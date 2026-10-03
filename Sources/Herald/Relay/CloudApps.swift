import Foundation

/// Keeps the `cloud.*` apps in step with the relay's agent keys (issues #85, #86): an OAuth connector's app is named with the client's own
/// name (`client_name`, which the relay lists as `displayName`), not the key's truncated slug, and an app with no icon gets the
/// automatic one. The slug stays in the app id only.
public enum CloudApps {
    public static func appID(for key: RelayKeyInfo) -> String { AgentIdentity.cloudPrefix + HeraldAgent.slug(key.name) }

    /// Renames the apps of OAuth connectors and gives icon-less cloud apps their icon. Only apps that exist are touched (a key that
    /// never sent anything has no app). Returns the apps renamed.
    @discardableResult
    public static func reconcile(keys: [RelayKeyInfo], registry: AppRegistry, manifests: ManifestStore? = nil, supportDirectory: URL,
                                 roots: AgentIconSources.Roots = .standard()) -> [String] {
        var renamed: [String] = []
        for k in keys where k.isActive && k.isOAuth {
            let app = appID(for: k)
            guard let rec = registry.record(for: app),
                  let name = k.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            if rec.registration.appName != name {
                registry.register(HeraldAppRegistration(app: app, appName: name))
                renamed.append(app)
            }
            if var m = manifests?.get(app: app), m.appName != name { m.appName = name; _ = manifests?.put(m) }
        }
        AutoIcon.applyToIconless(registry: registry, supportDirectory: supportDirectory, keys: keys, roots: roots)
        return renamed
    }
}
