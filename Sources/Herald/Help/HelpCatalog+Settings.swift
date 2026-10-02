import Foundation

extension HelpEntry {
    static let tooltipLevel = HelpEntry("settings.tooltips", "Tooltips", "how much a tooltip says: just the control's name, or its name and what it does")
    static let apiPort = HelpEntry("settings.apiPort", "Port", "the port Herald's local API listens on")
    static let apiApply = HelpEntry("settings.apiApply", "Apply port", "restart the local API on the port you typed")
    static let apiReset = HelpEntry("settings.apiReset", "Reset port", "go back to the default port and restart the local API")
    static let revealToken = HelpEntry("settings.revealToken", "Reveal token file", "show the API token file in Finder")
    static let launchAtLogin = HelpEntry("settings.launchAtLogin", "Launch at login", "start Herald automatically when you log in")
    static let muteSounds = HelpEntry("settings.muteSounds", "Mute all sounds", "silence every notification sound")
    static let defaultSound = HelpEntry("settings.defaultSound", "Sound", "the sound this app's notifications play by default")
    static let chooseSound = HelpEntry("settings.chooseSound", "Choose sound file", "pick your own audio file as this app's sound")
    static let stayUntilDismissed = HelpEntry("settings.stayUntilDismissed", "Stay until dismissed", "keep banners on screen until you dismiss them")
    static let autoDismiss = HelpEntry("settings.autoDismiss", "Auto-dismiss timeout", "seconds before a banner dismisses itself; 0 means never")
    static let openTemplates = HelpEntry("settings.openTemplates", "Templates", "open the template editor for this app")
    static let allowCommands = HelpEntry("settings.allowCommands", "Allow commands", "let this app's notification buttons run shell commands as you")
    static let allowCallbacks = HelpEntry("settings.allowCallbacks", "Allow callbacks", "let this app's callback buttons post to this remote host")
    static let revealScripts = HelpEntry("settings.revealScripts", "Reveal scripts folder", "show the actions scripts folder in Finder")
    static let refreshScripts = HelpEntry("settings.refreshScripts", "Refresh scripts", "rescan the scripts folder")
    static let showActionLog = HelpEntry("settings.showActionLog", "Show log", "reveal the actions log file")
    static let revokeApproval = HelpEntry("settings.revokeApproval", "Revoke approval", "withdraw the approval for this template's commands")
    static let displayScreen = HelpEntry("settings.displayScreen", "Display", "the screen this app's banners appear on")
    static let screenCorner = HelpEntry("settings.screenCorner", "Screen corner", "the corner this app's banners appear in")
    static let muteBanners = HelpEntry("settings.muteBanners", "Mute banners", "hide this app's banners; notifications still reach History")
    static let stackNotifications = HelpEntry("settings.stackNotifications", "Stack notifications", "how this app's simultaneous banners are grouped")
    static let voiceEngine = HelpEntry("settings.voiceEngine", "Speech engine", "which engine speaks notifications, or off")
    static let speakTest = HelpEntry("settings.speakTest", "Speak test text", "speak the test text with the current voice")
    static let testText = HelpEntry("settings.testText", "Test text", "the sentence to speak when you press Speak")
    static let speakApp = HelpEntry("settings.speakApp", "Speak this app", "read this app's notifications aloud")
    static let urgentBreaksQuiet = HelpEntry("settings.urgentBreaksQuiet", "Urgent breaks quiet hours", "let this app's urgent notifications speak during quiet hours")
    static let appVoice = HelpEntry("settings.appVoice", "Voice for this app", "the voice used for this app, or the default voice")
    static let showKokoro = HelpEntry("settings.showKokoro", "Show in Finder", "reveal the Kokoro folder in Finder")
    static let useExistingKokoro = HelpEntry("settings.useExistingKokoro", "Use existing Kokoro", "link the Kokoro installation already at ~/.claude/tts")
    static let downloadKokoro = HelpEntry("settings.downloadKokoro", "Download Kokoro", "download the Kokoro models and set up its Python environment")
    static let cancelKokoro = HelpEntry("settings.cancelKokoro", "Cancel download", "stop downloading Kokoro")
    static let defaultVoice = HelpEntry("settings.defaultVoice", "Voice", "the voice used to speak notifications")
    static let speechSpeed = HelpEntry("settings.speechSpeed", "Speed", "how fast notifications are spoken")
    static let quietAddWindow = HelpEntry("settings.quietAddWindow", "Add window", "add a daily quiet-hours window")
    static let quietOneHour = HelpEntry("settings.quietOneHour", "Quiet for 1 hour", "go quiet right now for one hour")
    static let quietResume = HelpEntry("settings.quietResume", "Resume now", "end the current quiet period")
    static let quietDay = HelpEntry("settings.quietDay", "Day of week", "turn this window on or off for this day")
    static let quietDelete = HelpEntry("settings.quietDelete", "Delete window", "remove this quiet-hours window")
    static let quietFrom = HelpEntry("settings.quietFrom", "Start time", "when this quiet window begins")
    static let quietUntil = HelpEntry("settings.quietUntil", "End time", "when this quiet window ends")
    static let quietSpeech = HelpEntry("settings.quietSpeech", "Silence speech", "hold back spoken notifications during this window")
    static let quietSounds = HelpEntry("settings.quietSounds", "Silence sounds", "mute notification sounds during this window")
    static let quietBanners = HelpEntry("settings.quietBanners", "Hide banners", "hold back banners during this window")
    static let quietSummary = HelpEntry("settings.quietSummary", "Speak queued messages", "read out the messages held back once the window ends")
    static let mcpReveal = HelpEntry("settings.mcpReveal", "Reveal server file", "show the MCP server executable in Finder")
    static let mcpTest = HelpEntry("settings.mcpTest", "Test connection", "start the MCP server and check that it answers")
    static let mcpInstallCLI = HelpEntry("settings.mcpInstallCLI", "Install command line tool", "install the herald command in your shell path")
    static let mcpCopyConfig = HelpEntry("settings.mcpCopyConfig", "Copy generic config", "copy the JSON config and stdio command for any MCP client")
    static let mcpInstallClient = HelpEntry("settings.mcpInstallClient", "Install or reinstall", "add or refresh Herald's entry in this MCP client")
}

extension HeraldHelpCatalog {
    static let settings: [HelpEntry] = [HelpEntry.tooltipLevel,
        .apiPort,
        .apiApply,
        .apiReset,
        .revealToken,
        .launchAtLogin,
        .muteSounds,
        .defaultSound,
        .chooseSound,
        .stayUntilDismissed,
        .autoDismiss,
        .openTemplates,
        .allowCommands,
        .allowCallbacks,
        .revealScripts,
        .refreshScripts,
        .showActionLog,
        .revokeApproval,
        .displayScreen,
        .screenCorner,
        .muteBanners,
        .stackNotifications,
        .voiceEngine,
        .speakTest,
        .testText,
        .speakApp,
        .urgentBreaksQuiet,
        .appVoice,
        .showKokoro,
        .useExistingKokoro,
        .downloadKokoro,
        .cancelKokoro,
        .defaultVoice,
        .speechSpeed,
        .quietAddWindow,
        .quietOneHour,
        .quietResume,
        .quietDay,
        .quietDelete,
        .quietFrom,
        .quietUntil,
        .quietSpeech,
        .quietSounds,
        .quietBanners,
        .quietSummary,
        .mcpReveal,
        .mcpTest,
        .mcpInstallCLI,
        .mcpCopyConfig,
        .mcpInstallClient,
    ]
}
