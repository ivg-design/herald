import Foundation

extension HelpEntry {
    // Authoring controls: id, name, detail, shortcut.
    static let designTemplate = HelpEntry("authoring.designTemplate", "Design template", "The Designer, where this app's banner grid and components are laid out")
    static let clear = HelpEntry("authoring.clear", "Clear", "Empties every field of this form so a new notification starts from scratch")
    static let copyAs = HelpEntry("authoring.copyAs", "Copy as", "This notification written as a ready-to-run call in the CLI, curl, Swift and other forms")
    static let copyFormat = HelpEntry("authoring.copyFormat", "Copy format", "The same notification written out in this one format and placed on the clipboard")
    static let saveAsTemplate = HelpEntry("authoring.saveAsTemplate", "Save as template", "A reusable template that keeps this look, text and buttons for later notifications")
    static let sendNow = HelpEntry("authoring.sendNow", "Send now", "Posts this notification as a real banner right away", "\u{2318}\u{21A9}")
    static let saveSheetName = HelpEntry("authoring.saveSheetName", "Template name", "The name this template is stored under and that notifications use to ask for it")
    static let saveSheetCancel = HelpEntry("authoring.saveSheetCancel", "Cancel", "Closes the sheet and leaves the template unsaved", "Esc")
    static let saveSheetSave = HelpEntry("authoring.saveSheetSave", "Save template", "Stores the template under the name entered above", "\u{21A9}")
    static let appPicker = HelpEntry("authoring.appPicker", "Registered apps", "The app that issues the notification; any app id works, registered or not")
    static let template = HelpEntry("authoring.template", "Template", "A saved template whose look, text and buttons this notification starts from")
    static let browseImage = HelpEntry("authoring.browseImage", "Browse for image", "A picture from disk shown as the banner image")
    static let stayOnScreen = HelpEntry("authoring.stayOnScreen", "Stay on screen", "How long the banner remains: the app default, until dismissed, or a set number of seconds")
    static let snoozeMenu = HelpEntry("authoring.snoozeMenu", "Snooze menu", "A menu on the banner that lets the reader postpone it for a chosen time")
    static let reminderButton = HelpEntry("authoring.reminderButton", "Add to Reminders button", "A banner button that turns the notification into an item in Apple Reminders")
    static let reminderDueToggle = HelpEntry("authoring.reminderDueToggle", "Reminder due date", "Whether the reminder created from this banner carries a due date")
    static let reminderDue = HelpEntry("authoring.reminderDue", "Due", "The date and time the new reminder falls due")
    static let priority = HelpEntry("authoring.priority", "Priority", "How urgent the notification is, which decides whether it may break through quiet hours")
    static let removeMetadata = HelpEntry("authoring.removeMetadata", "Remove row", "Deletes this metadata key and its value from the notification")
    static let addMetadata = HelpEntry("authoring.addMetadata", "Add row", "A new key and value carried with the notification for templates and actions to use")
    static let sound = HelpEntry("authoring.sound", "Sound", "The sound played when the banner appears")
    static let previewSound = HelpEntry("authoring.previewSound", "Preview sound", "Plays the chosen sound once so it can be judged before sending")
    static let browseSound = HelpEntry("authoring.browseSound", "Browse for sound", "An audio file from disk used as the notification sound")
    static let addButton = HelpEntry("authoring.addButton", "Add button", "A new action button shown on the banner")
    static let buttonAction = HelpEntry("authoring.buttonAction", "Button action", "What the button does when used: open a URL, call back the sender or run a command")
    static let buttonStyle = HelpEntry("authoring.buttonStyle", "Button style", "The button's look: default, destructive or cancel")
    static let removeButton = HelpEntry("authoring.removeButton", "Remove button", "Deletes this action button from the banner")
    static let accentColor = HelpEntry("authoring.accentColor", "Accent color", "A color that tints the banner's accent elements")
    static let accentPicker = HelpEntry("authoring.accentPicker", "Accent color picker", "The color panel used to choose the banner's accent color")
    static let newTemplate = HelpEntry("authoring.newTemplate", "New template", "An empty template with nothing in it yet")
    static let layout = HelpEntry("authoring.layout", "Layout", "How the banner arranges its image and text")
    static let showSubtitle = HelpEntry("authoring.showSubtitle", "Show subtitle", "Whether the banner shows its secondary line under the title")
    static let showBody = HelpEntry("authoring.showBody", "Show body", "Whether the banner shows the main message text")
    static let showTime = HelpEntry("authoring.showTime", "Show time", "Whether the banner shows when the notification arrived")
    static let bodyLines = HelpEntry("authoring.bodyLines", "Body lines", "The most lines of message text the banner shows before cutting it off")
    static let triStatePersistent = HelpEntry("authoring.triStatePersistent", "Stay until dismissed", "Whether this template keeps banners on screen until dismissed, or inherits the app's choice")
    static let triStateSnooze = HelpEntry("authoring.triStateSnooze", "Snooze menu", "Whether this template adds a snooze menu to its banners, or inherits the app's choice")
    static let openInDesigner = HelpEntry("authoring.openInDesigner", "Open in Designer", "The saved version of this grid template, opened in the visual Designer")
    static let deleteTemplate = HelpEntry("authoring.deleteTemplate", "Delete", "Removes this saved template for good")
    static let duplicateTemplate = HelpEntry("authoring.duplicateTemplate", "Duplicate", "A copy of this template saved under a new name")
    static let saveTemplate = HelpEntry("authoring.saveTemplate", "Save", "Writes your changes to this template on disk", "\u{2318}S")
    static let fillFromLast = HelpEntry("authoring.fillFromLast", "Fill from last notification", "The metadata of this app's newest notification, copied into the sample rows")
    static let removeSample = HelpEntry("authoring.removeSample", "Remove row", "Deletes this sample key and value from the preview data")
    static let addSample = HelpEntry("authoring.addSample", "Add row", "A new key and value of sample data used to fill the preview")
    static let addUsed = HelpEntry("authoring.addUsed", "Add used keys", "Sample rows for every placeholder the template uses that has none yet")
    static let replaySpeech = HelpEntry("authoring.replaySpeech", "Play again", "Speaks this notification's message aloud again")
}

extension HeraldHelpCatalog {
    static let authoring: [HelpEntry] = [
        .designTemplate,
        .clear,
        .copyAs,
        .copyFormat,
        .saveAsTemplate,
        .sendNow,
        .saveSheetName,
        .saveSheetCancel,
        .saveSheetSave,
        .appPicker,
        .template,
        .browseImage,
        .stayOnScreen,
        .snoozeMenu,
        .reminderButton,
        .reminderDueToggle,
        .reminderDue,
        .priority,
        .removeMetadata,
        .addMetadata,
        .sound,
        .previewSound,
        .browseSound,
        .addButton,
        .buttonAction,
        .buttonStyle,
        .removeButton,
        .accentColor,
        .accentPicker,
        .newTemplate,
        .layout,
        .showSubtitle,
        .showBody,
        .showTime,
        .bodyLines,
        .triStatePersistent,
        .triStateSnooze,
        .openInDesigner,
        .deleteTemplate,
        .duplicateTemplate,
        .saveTemplate,
        .fillFromLast,
        .removeSample,
        .addSample,
        .addUsed,
        .replaySpeech,
    ]
}
