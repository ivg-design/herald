import Foundation

extension HelpEntry {
    // Authoring controls: id, name, detail, shortcut.
    static let designTemplate = HelpEntry("authoring.designTemplate", "Design template", "open the Designer to lay out the banner for this app")
    static let clear = HelpEntry("authoring.clear", "Clear", "reset every field in the form")
    static let copyAs = HelpEntry("authoring.copyAs", "Copy as", "copy this notification as code (CLI, curl, Swift and more)")
    static let copyFormat = HelpEntry("authoring.copyFormat", "Copy format", "copy this notification in this format")
    static let saveAsTemplate = HelpEntry("authoring.saveAsTemplate", "Save as template", "store this look, text and buttons as a reusable template")
    static let sendNow = HelpEntry("authoring.sendNow", "Send now", "show this notification now", "\u{2318}\u{21A9}")
    static let saveSheetName = HelpEntry("authoring.saveSheetName", "Template name", "the name to save this template under")
    static let saveSheetCancel = HelpEntry("authoring.saveSheetCancel", "Cancel", "close without saving", "Esc")
    static let saveSheetSave = HelpEntry("authoring.saveSheetSave", "Save template", "store the template under this name", "\u{21A9}")
    static let appPicker = HelpEntry("authoring.appPicker", "Registered apps", "pick one of the registered apps; any other id works too")
    static let template = HelpEntry("authoring.template", "Template", "start from a saved template, or none")
    static let browseImage = HelpEntry("authoring.browseImage", "Browse for image", "choose an image file")
    static let stayOnScreen = HelpEntry("authoring.stayOnScreen", "Stay on screen", "how long the banner stays: default, until dismissed or auto-dismiss")
    static let snoozeMenu = HelpEntry("authoring.snoozeMenu", "Snooze menu", "add a snooze menu to the banner")
    static let reminderButton = HelpEntry("authoring.reminderButton", "Add to Reminders button", "add a button that creates a reminder")
    static let reminderDueToggle = HelpEntry("authoring.reminderDueToggle", "Reminder due date", "give the reminder a due date")
    static let reminderDue = HelpEntry("authoring.reminderDue", "Due", "when the reminder is due")
    static let priority = HelpEntry("authoring.priority", "Priority", "how urgent the notification is")
    static let removeMetadata = HelpEntry("authoring.removeMetadata", "Remove row", "delete this metadata row")
    static let addMetadata = HelpEntry("authoring.addMetadata", "Add row", "add a metadata key and value")
    static let sound = HelpEntry("authoring.sound", "Sound", "the sound played with the banner")
    static let previewSound = HelpEntry("authoring.previewSound", "Preview sound", "play the selected sound")
    static let browseSound = HelpEntry("authoring.browseSound", "Browse for sound", "choose an audio file")
    static let addButton = HelpEntry("authoring.addButton", "Add button", "add an action button to the banner")
    static let buttonAction = HelpEntry("authoring.buttonAction", "Button action", "what the button does: open a URL, call back or run a command")
    static let buttonStyle = HelpEntry("authoring.buttonStyle", "Button style", "default, destructive or cancel look")
    static let removeButton = HelpEntry("authoring.removeButton", "Remove button", "delete this button")
    static let accentColor = HelpEntry("authoring.accentColor", "Accent color", "tint the banner with a color")
    static let accentPicker = HelpEntry("authoring.accentPicker", "Accent color picker", "choose the accent color")
    static let newTemplate = HelpEntry("authoring.newTemplate", "New template", "start an empty template")
    static let layout = HelpEntry("authoring.layout", "Layout", "how the banner arranges image and text")
    static let showSubtitle = HelpEntry("authoring.showSubtitle", "Show subtitle", "display the subtitle line")
    static let showBody = HelpEntry("authoring.showBody", "Show body", "display the body text")
    static let showTime = HelpEntry("authoring.showTime", "Show time", "display the time the notification arrived")
    static let bodyLines = HelpEntry("authoring.bodyLines", "Body lines", "the most body lines to show")
    static let triStatePersistent = HelpEntry("authoring.triStatePersistent", "Stay until dismissed", "inherit the app setting, or force on or off")
    static let triStateSnooze = HelpEntry("authoring.triStateSnooze", "Snooze menu", "inherit the app setting, or force on or off")
    static let openInDesigner = HelpEntry("authoring.openInDesigner", "Open in Designer", "edit this grid template visually; opens the saved version")
    static let deleteTemplate = HelpEntry("authoring.deleteTemplate", "Delete", "delete this saved template")
    static let duplicateTemplate = HelpEntry("authoring.duplicateTemplate", "Duplicate", "copy this template under a new name")
    static let saveTemplate = HelpEntry("authoring.saveTemplate", "Save", "store your changes to this template", "\u{2318}S")
    static let fillFromLast = HelpEntry("authoring.fillFromLast", "Fill from last notification", "copy the metadata of this app's newest notification")
    static let removeSample = HelpEntry("authoring.removeSample", "Remove row", "delete this sample value")
    static let addSample = HelpEntry("authoring.addSample", "Add row", "add a sample value")
    static let addUsed = HelpEntry("authoring.addUsed", "Add used keys", "add rows for the placeholders the template uses")
    static let replaySpeech = HelpEntry("authoring.replaySpeech", "Play again", "play the spoken message again")
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
