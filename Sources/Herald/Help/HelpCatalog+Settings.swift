import Foundation

extension HelpEntry {
    static let tooltipLevel = HelpEntry("settings.tooltips", "Tooltips", "How much a tooltip says: just the control's name, or its name and what it does")
    static let appVersion = HelpEntry("settings.appVersion", "Version", "The installed Herald version and build number")
    static let apiPort = HelpEntry("settings.apiPort", "Port", "The port Herald's local API listens on for notifications from other programs")
    static let apiApply = HelpEntry("settings.apiApply", "Apply port", "Restarts the local API on the port typed above")
    static let apiReset = HelpEntry("settings.apiReset", "Reset port", "Returns the local API to its default port and restarts it")
    static let revealToken = HelpEntry("settings.revealToken", "Reveal token file", "The file holding the API token that clients must send, shown in Finder")
    static let launchAtLogin = HelpEntry("settings.launchAtLogin", "Launch at login", "Whether Herald starts by itself when you log in")
    static let muteSounds = HelpEntry("settings.muteSounds", "Mute all sounds", "Silences the sound of every notification from every app")
    static let defaultSound = HelpEntry("settings.defaultSound", "Sound", "The sound this app's notifications play unless one names its own")
    static let chooseSound = HelpEntry("settings.chooseSound", "Choose sound file", "Your own audio file used as this app's sound")
    static let stayUntilDismissed = HelpEntry("settings.stayUntilDismissed", "Stay until dismissed", "Keeps this app's banners on screen until you dismiss them")
    static let autoDismiss = HelpEntry("settings.autoDismiss", "Auto-dismiss timeout", "Seconds before a banner removes itself; 0 means it never does")
    static let openTemplates = HelpEntry("settings.openTemplates", "Templates", "The template editor for this app's banners")
    static let allowCommands = HelpEntry("settings.allowCommands", "Allow commands", "Whether this app's notification buttons may run shell commands as you")
    static let allowCallbacks = HelpEntry("settings.allowCallbacks", "Allow callbacks", "Whether this app's callback buttons may post to this remote host")
    static let revealScripts = HelpEntry("settings.revealScripts", "Reveal scripts folder", "The folder of scripts that action buttons can run, shown in Finder")
    static let refreshScripts = HelpEntry("settings.refreshScripts", "Refresh scripts", "Rescans the scripts folder for added or removed scripts")
    static let showActionLog = HelpEntry("settings.showActionLog", "Show log", "The log file recording every action button that ran")
    static let revokeApproval = HelpEntry("settings.revokeApproval", "Revoke approval", "Withdraws the approval given to this template's commands, so they ask again")
    static let displayScreen = HelpEntry("settings.displayScreen", "Display", "The screen this app's banners appear on")
    static let screenCorner = HelpEntry("settings.screenCorner", "Screen corner", "The corner of the screen this app's banners appear in")
    static let muteBanners = HelpEntry("settings.muteBanners", "Mute banners", "Hides this app's banners while its notifications still reach History")
    static let stackNotifications = HelpEntry("settings.stackNotifications", "Stack notifications", "How this app's simultaneous banners are grouped on screen")
    static let voiceEngine = HelpEntry("settings.voiceEngine", "Speech engine", "The engine that speaks notifications aloud, or Off for silence")
    static let speakTest = HelpEntry("settings.speakTest", "Speak test text", "Speaks the test text in the current voice so it can be judged")
    static let testText = HelpEntry("settings.testText", "Test text", "The sentence spoken by the voice test")
    static let speakApp = HelpEntry("settings.speakApp", "Speak this app", "Whether this app's notifications are read aloud")
    static let urgentBreaksQuiet = HelpEntry("settings.urgentBreaksQuiet", "Urgent breaks quiet hours", "Lets this app's urgent notifications speak even during quiet hours")
    static let appVoice = HelpEntry("settings.appVoice", "Voice for this app", "The voice used for this app, or the default voice")
    static let showKokoro = HelpEntry("settings.showKokoro", "Show in Finder", "The Kokoro folder, shown in Finder")
    static let useExistingKokoro = HelpEntry("settings.useExistingKokoro", "Use existing Kokoro", "The Kokoro installation already at ~/.claude/tts, linked instead of downloaded again")
    static let downloadKokoro = HelpEntry("settings.downloadKokoro", "Download Kokoro", "Kokoro, the on-device neural voice, with its models and Python environment")
    static let cancelKokoro = HelpEntry("settings.cancelKokoro", "Cancel download", "Stops the Kokoro download in progress")
    static let defaultVoice = HelpEntry("settings.defaultVoice", "Voice", "The voice used to speak notifications unless an app picks its own")
    static let speechSpeed = HelpEntry("settings.speechSpeed", "Speed", "How fast notifications are spoken")
    static let quietAddWindow = HelpEntry("settings.quietAddWindow", "Add window", "A daily time window during which notifications are quieted")
    static let quietOneHour = HelpEntry("settings.quietOneHour", "Quiet for 1 hour", "Starts quiet hours immediately and ends them after one hour")
    static let quietResume = HelpEntry("settings.quietResume", "Resume now", "Ends the current quiet period right away")
    static let quietDay = HelpEntry("settings.quietDay", "Day of week", "Whether this window applies on this day of the week")
    static let quietDelete = HelpEntry("settings.quietDelete", "Delete window", "Removes this quiet-hours window")
    static let quietFrom = HelpEntry("settings.quietFrom", "Start time", "The time of day this quiet window begins")
    static let quietUntil = HelpEntry("settings.quietUntil", "End time", "The time of day this quiet window ends")
    static let quietSpeech = HelpEntry("settings.quietSpeech", "Silence speech", "Holds back spoken notifications during this window")
    static let quietSounds = HelpEntry("settings.quietSounds", "Silence sounds", "Mutes notification sounds during this window")
    static let quietBanners = HelpEntry("settings.quietBanners", "Hide banners", "Holds back banners during this window")
    static let quietSummary = HelpEntry("settings.quietSummary", "Speak queued messages", "Reads aloud the messages held back once the window ends")
    static let mcpReveal = HelpEntry("settings.mcpReveal", "Reveal server file", "The MCP server executable that AI clients launch, shown in Finder")
    static let mcpTest = HelpEntry("settings.mcpTest", "Test connection", "Starts the MCP server and checks that it answers")
    static let mcpInstallCLI = HelpEntry("settings.mcpInstallCLI", "Install command line tool", "Installs the herald command into your shell path")
    static let mcpCopyConfig = HelpEntry("settings.mcpCopyConfig", "Copy generic config", "The JSON config and stdio command that any MCP client can use, copied to the clipboard")
    static let mcpInstallClient = HelpEntry("settings.mcpInstallClient", "Install or reinstall", "Adds or refreshes Herald's entry in this MCP client's configuration")
}

extension HeraldHelpCatalog {
    static let settings: [HelpEntry] = [HelpEntry.tooltipLevel,
        .appVersion,
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
