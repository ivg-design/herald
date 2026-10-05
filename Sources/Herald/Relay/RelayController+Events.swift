import Foundation
import HeraldClient

/// MCP Events: a cloud agent subscribes with a webhook and the relay calls it when the user answers one of that agent's
/// notifications. The connector's approval is the only authorisation: subscribing asks nothing more of the user. Herald shows
/// the subscriptions and can end one; revoking the connector ends all of its subscriptions.
extension RelayController {
    /// What the relay holds now. A relay that predates events (404) leaves `events` nil.
    func refreshEvents() async {
        guard let api = client.api, isPaired else { return }
        if let e = try? await api.events() { events = e; controller.changed() }
    }

    func removeEventSubscription(id: String) async throws {
        guard let api = client.api, isPaired else { throw RelayError.notPaired }
        try await api.removeEventSubscription(id: id)
        await refreshEvents()
    }

    // MARK: RelayBackend

    func relayEvents() async throws -> RelayEvents {
        guard let api = client.api, isPaired else { throw RelayError.notPaired }
        let e = try await api.events()
        events = e
        controller.changed()
        return e
    }

    func relayRemoveEventSubscription(id: String) async throws { try await removeEventSubscription(id: id) }
}
