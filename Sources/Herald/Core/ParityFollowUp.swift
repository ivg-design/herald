import Foundation

// `PUT /v1/templates/follow-up` (the `set_follow_up` tool, `herald template follow-up`) and the follow-up rows of the
// approvals list. A follow-up runs one action when a banner is left unattended (HeraldFollowUp). This route edits the
// template's follow-up; it reports whether the action still needs the person's approval and NEVER grants it.

extension ParityService {
    /// How a follow-up's action stands with the approval gates, computed and never granted.
    func followUpApproval(_ r: HeraldResolvedFollowUp, app: String, template: HeraldTemplate?, templateName: String) -> String {
        switch actionRunner.authorization(for: r.action, origin: r.origin, app: app, record: registry.record(for: app),
                                          template: template, templateName: templateName, approvals: approvals) {
        case .run: return actionRunner.approvalKey(for: r.action) == nil ? "none" : "approved"
        case .askTemplate: return "needs-approval"
        case .askApp: return "app-permission-needed"
        case .denied: return "app-not-allowed"
        }
    }

    /// The `after` field as seconds: a number, or a string such as "10m".
    private func followUpSeconds(_ o: [String: Any]) throws -> Double? {
        guard let v = o["after"], !(v is NSNull) else { return nil }
        if let s = v as? String {
            guard let n = HeraldFollowUp.parseDuration(s) else {
                throw BackendError(400, "invalid field: after (seconds as a number, or a string such as \"90s\", \"10m\" or \"2h\")")
            }
            return n
        }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        throw BackendError(400, "invalid field: after (seconds as a number, or a string such as \"10m\")")
    }

    func setFollowUp(_ req: HTTPRequest) throws -> HTTPResponse {
        let o = try body(req)
        let app = try requiredString(o, "app")
        let named = try optionalString(o, "template")
        let enabled = o["enabled"] as? Bool
        if o["enabled"] != nil, !(o["enabled"] is NSNull), enabled == nil { throw BackendError(400, "invalid field: enabled (true or false)") }
        let shortcut = try optionalString(o, "shortcut"), script = try optionalString(o, "script"), command = try optionalString(o, "command")
        let ref = try optionalString(o, "actionRef"), input = try optionalString(o, "input"), label = try optionalString(o, "label")
        let after = try followUpSeconds(o)
        let chosen = [("shortcut", shortcut), ("script", script), ("command", command), ("actionRef", ref)].filter { $0.1 != nil }.map(\.0)
        let nothingElse = chosen.isEmpty && after == nil && input == nil && label == nil

        // The template to edit.
        var manifest = manifests.get(app: app)
        var template: HeraldTemplate
        var createdTemplate = false
        var newManifest = false
        if let named {
            if templates.get(app: app, name: named) == nil {
                if BuiltinTemplates.isBuiltin(named) {
                    throw BackendError(400, "\(named) is a built-in layout and read-only; duplicate_template it first, then set the follow-up on the copy (or omit `template` to use the app's default)")
                }
                throw BackendError(404, "template not found: \(named)")
            }
            template = templates.get(app: app, name: named)!
        } else if let d = manifest?.defaultTemplate, !d.isEmpty, let stored = templates.get(app: app, name: d) {
            template = stored
        } else {
            // The app's notifications use a built-in layout: keep it as a stored copy, which becomes the default.
            let layoutName = manifest?.defaultTemplate.flatMap { BuiltinTemplates.isBuiltin($0) ? $0 : nil } ?? PreviewPlan.defaultTemplateName
            var copy = BuiltinTemplates.named(layoutName, app: app) ?? BuiltinTemplates.template(layout: .imageLeft, app: app)
            let taken = Set(templates.list(app: app).map(\.name))
            var name = "default", n = 2
            while taken.contains(name) { name = "default-\(n)"; n += 1 }
            copy.name = name; copy.app = app
            template = copy
            createdTemplate = true
            if manifest == nil {
                manifest = HeraldManifest(app: app, appName: registry.record(for: app)?.displayName)
                newManifest = true
            }
            manifest?.defaultTemplate = name
        }

        // The follow-up.
        let followUp: HeraldFollowUp
        if enabled == false {
            guard nothingElse else { throw BackendError(400, "enabled: false switches the follow-up off and takes no other follow-up field") }
            followUp = HeraldFollowUp(enabled: false)
        } else {
            guard let after else { throw BackendError(400, "missing field: after (seconds, or a string such as \"10m\")") }
            guard chosen.count == 1 else {
                throw BackendError(400, chosen.isEmpty ? "give the action: one of shortcut, script, command or actionRef"
                                                      : "give the action once: one of shortcut, script, command or actionRef (got \(chosen.joined(separator: ", ")))")
            }
            if (input != nil) && (command != nil || ref != nil) { throw BackendError(400, "input goes with a shortcut or a script") }
            if let ref {
                let offered = FollowUpResolver.sampleCandidates(manifest: manifest, template: template)
                guard let found = offered.first(where: { $0.action.id.caseInsensitiveCompare(ref) == .orderedSame })
                        ?? offered.first(where: { $0.action.label.caseInsensitiveCompare(ref) == .orderedSame }) else {
                    let ids = offered.map(\.action.id)
                    throw BackendError(400, "actionRef '\(ref)' is not an action this app offers" + (ids.isEmpty ? "" : " (\(ids.joined(separator: ", ")))")
                                       + "; use shortcut, script or command to name the action itself")
                }
                if let why = HeraldFollowUp.kindProblem(found.action.kind) { throw BackendError(400, "actionRef '\(ref)': \(why)") }
                followUp = HeraldFollowUp(after: after, actionRef: found.action.id, enabled: nil)
            } else {
                var action: HeraldAction
                if let shortcut { action = HeraldAction(id: "follow-up", label: label ?? shortcut, kind: .shortcut, shortcut: shortcut, input: input) }
                else if let script {
                    guard HeraldScriptName.isPlain(script) else { throw BackendError(400, "script must be a plain file name in Herald's scripts folder, not a path") }
                    action = HeraldAction(id: "follow-up", label: label ?? script, kind: .script, script: script, input: input)
                } else {
                    action = HeraldAction(id: "follow-up", label: label ?? "Follow-up", kind: .command, command: command)
                }
                action.label = action.label.trimmingCharacters(in: .whitespaces)
                followUp = HeraldFollowUp(after: after, action: action, enabled: nil)
            }
        }
        if let first = followUp.problems(path: "followUp").first(where: { $0.isError }) {
            throw BackendError(400, "\(first.path): \(first.message)")
        }
        template.followUp = followUp
        let issues = template.validate(manifest: manifest).filter(\.isError)
        guard issues.isEmpty else {
            throw BackendError(400, "invalid template: " + issues.map { ($0.cellId.map { "cell \($0): " } ?? "") + $0.path + ": " + $0.message }.joined(separator: "; "))
        }

        try saveTemplate(template)
        if createdTemplate, let manifest { try saveManifest(manifest) }

        // Where the follow-up stands with the gates. Computed, never granted.
        let resolved = followUp.isEnabled ? FollowUpResolver.resolveForTemplate(manifest: manifest, template: template) : nil
        var out: [String: Any] = ["saved": true, "app": app, "template": template.name, "createdTemplate": createdTemplate,
                                  "followUp": Self.jsonObject(followUp)]
        if createdTemplate { out["manifestCreated"] = newManifest; out["defaultTemplate"] = template.name }
        var note: String
        if let resolved {
            let approval = followUpApproval(resolved, app: app, template: template, templateName: template.name)
            out["action"] = Self.jsonObject(resolved.action)
            out["origin"] = resolved.origin.rawValue
            out["approval"] = approval
            out["needsApproval"] = ["needs-approval", "app-permission-needed", "app-not-allowed"].contains(approval)
            note = "Approval stays with the person at the Mac: the banner asks the first time the action would run, and Always allow lets later follow-ups run unattended. Nothing was approved here."
            if approval == "app-not-allowed" { note += " The app has not registered to run commands, scripts and Shortcuts, so it cannot run until it does and the person allows it in Settings > Apps." }
            if approval == "app-permission-needed" { note += " The person enables \"Allow this app to run commands, scripts and Shortcuts\" in Settings > Apps." }
            if resolved.action.kind == .shortcut { note += " list_shortcuts names the installed Shortcuts." }
        } else {
            out["action"] = NSNull(); out["origin"] = NSNull(); out["approval"] = "none"; out["needsApproval"] = false
            note = followUp.isEnabled ? "The follow-up does not resolve to an action yet." : "The follow-up is switched off for this template."
        }
        out["note"] = note
        return Self.reply(out)
    }

    /// The `followUps` rows of the approvals list: every enabled template follow-up that runs code, and every manifest
    /// that declares one, with the state of its approval.
    func followUpRows() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        func row(app: String, template: String?, source: String, _ r: HeraldResolvedFollowUp, _ t: HeraldTemplate?) -> [String: Any] {
            var o: [String: Any] = ["app": app, "source": source, "action": r.action.label, "kind": r.action.kind.rawValue,
                                    "origin": r.origin.rawValue,
                                    "approval": followUpApproval(r, app: app, template: t, templateName: template ?? "")]
            if let template { o["template"] = template }
            return o
        }
        for t in templates.list() where t.followUp?.isEnabled == true {
            guard let r = FollowUpResolver.resolveForTemplate(manifest: manifests.get(app: t.app), template: t),
                  r.source == .template, actionRunner.approvalKey(for: r.action) != nil else { continue }
            rows.append(row(app: t.app, template: t.name, source: "template", r, t))
        }
        for m in manifests.list() where m.followUp?.isEnabled == true {
            guard let r = FollowUpResolver.resolveForTemplate(manifest: m, template: nil) else { continue }
            rows.append(row(app: m.app, template: nil, source: "manifest", r, nil))
        }
        return rows.sorted { ($0["app"] as? String ?? "") + ($0["template"] as? String ?? "") < ($1["app"] as? String ?? "") + ($1["template"] as? String ?? "") }
    }
}
