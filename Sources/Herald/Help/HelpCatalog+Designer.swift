import Foundation

extension HelpEntry {
    // Designer controls: id, name, detail, shortcut.
    static let designerPreviewDivider = HelpEntry("designer.previewDivider", "Resize preview", "drag to change how much room the live preview gets")
    static let designerModePicker = HelpEntry("designer.modePicker", "Mode", "switch between designing a template and sending a one-off notification")
    static let designerImportBundle = HelpEntry("designer.importBundle", "Import", "add a template bundle (.heraldtemplate) with its animations; you can also drop one on this window")
    static let designerExportBundle = HelpEntry("designer.exportBundle", "Export", "save this template and the animations it plays as a .heraldtemplate bundle")
    static let designerUndo = HelpEntry("designer.undo", "Undo", "revert the last edit to the template", "\u{2318}Z")
    static let designerRedo = HelpEntry("designer.redo", "Redo", "re-apply the edit you just undid", "\u{21E7}\u{2318}Z")
    static let designerMerge = HelpEntry("designer.merge", "Merge slots", "join the selected slots into one cell (shift-click to select several)")
    static let designerSplit = HelpEntry("designer.split", "Split cell", "cut a merged cell back into single slots")
    static let designerDuplicateComponent = HelpEntry("designer.duplicateComponent", "Duplicate component", "copy the selected component into the next free slot", "\u{2318}D")
    static let designerDeleteComponent = HelpEntry("designer.deleteComponent", "Delete component", "remove the selected component from the template", "\u{2318}\u{232B}")
    static let designerZoom = HelpEntry("designer.zoom", "Zoom", "open the zoom slider for this pane; pinch also zooms", "\u{2318}+ \u{2318}\u{2212} \u{2318}0")
    static let designerAppearance = HelpEntry("designer.appearance", "Preview appearance", "preview the banner in light or dark appearance")
    static let designerAbsentFields = HelpEntry("designer.absentFields", "Absent fields", "preview a field as missing to see how the template handles it")
    static let designerIssues = HelpEntry("designer.issues", "Template problems", "list the problems found in the template; click one to select its cell")
    static let designerSendTest = HelpEntry("designer.sendTest", "Send test", "show this banner on screen through Herald with the preview data")
    static let designerSave = HelpEntry("designer.save", "Save template", "save the template so notifications can use it", "\u{2318}S")
    static let designerFieldPresent = HelpEntry("designer.fieldPresent", "Field present", "untick to preview the banner without this field")
    static let designerAllPresent = HelpEntry("designer.allPresent", "All present", "mark every field as present again")
    static let designerZoomOut = HelpEntry("designer.zoomOut", "Zoom out", "make the pane smaller by one step", "\u{2318}\u{2212}")
    static let designerZoomSlider = HelpEntry("designer.zoomSlider", "Zoom level", "drag to set the zoom between 50% and 300%")
    static let designerZoomIn = HelpEntry("designer.zoomIn", "Zoom in", "make the pane bigger by one step", "\u{2318}+")
    static let designerZoomReset = HelpEntry("designer.zoomReset", "Reset zoom", "return to 100%", "\u{2318}0")
    static let designerPreviewSource = HelpEntry("designer.previewSource", "Preview data", "show sample data from the manifest, or the newest real notification")
    static let designerIssueRow = HelpEntry("designer.issueRow", "Problem", "select the cell this problem is about")
    static let designerIssuerPicker = HelpEntry("designer.issuerPicker", "Issuer", "choose which app's templates you are designing")
    static let designerDuplicateTemplate = HelpEntry("designer.duplicateTemplate", "Duplicate template", "save a copy of this template, with your current edits, under a new name")
    static let designerNewTemplate = HelpEntry("designer.newTemplate", "New template", "start a blank grid or one based on a standard layout")
    static let designerDeleteTemplate = HelpEntry("designer.deleteTemplate", "Delete template", "delete the selected template after confirming")
    static let designerSetDefault = HelpEntry("designer.setDefault", "Issuer default", "notifications from this issuer that name no template use this one")
    static let designerOldLayoutBadge = HelpEntry("designer.oldLayoutBadge", "Old layout", "this template uses the v1 layout and opens converted to a grid")
    static let designerDefaultBadge = HelpEntry("designer.defaultBadge", "Default template", "this is the template used when a notification names none")
    static let designerUnsavedDot = HelpEntry("designer.unsavedDot", "Unsaved changes", "this template has edits that are not saved yet")
    static let designerCustomField = HelpEntry("designer.customField", "Custom field", "a key the issuer may send in its metadata that the manifest does not declare; type it, then press Return")
    static let designerAddCustomField = HelpEntry("designer.addCustomField", "Add custom field", "add the typed key to the field list")
    static let designerAddAction = HelpEntry("designer.addAction", "Add action", "add a button to the banner: a shortcut, script, command, link, callback, snooze or dismiss")
    static let designerAddAsset = HelpEntry("designer.addAsset", "Add animation", "copy a .riv file into this issuer's assets folder")
    static let designerRemoveAsset = HelpEntry("designer.removeAsset", "Remove animation", "delete this .riv file from the issuer's assets folder")
    static let designerRemoveExtraValue = HelpEntry("designer.removeExtraValue", "Remove value", "delete this extra key and value")
    static let designerRemoveTemplateAction = HelpEntry("designer.removeTemplateAction", "Remove button", "delete this button you added")
    static let designerEditTemplateAction = HelpEntry("designer.editTemplateAction", "Edit button", "change this button's label, what it does and its look")
    static let designerResetIssuerAction = HelpEntry("designer.resetIssuerAction", "Reset button", "undo your rename, restyle or hiding and go back to what the issuer sent")
    static let designerMoveActionUp = HelpEntry("designer.moveActionUp", "Move button up", "place this button earlier in the row")
    static let designerMoveActionDown = HelpEntry("designer.moveActionDown", "Move button down", "place this button later in the row")
    static let designerHideAction = HelpEntry("designer.hideAction", "Show or hide button", "hide this issuer button from the banner, or show it again")
    static let designerActionStyle = HelpEntry("designer.actionStyle", "Button style", "choose default, destructive or cancel styling for this button")
    static let designerActionLabel = HelpEntry("designer.actionLabel", "Button label", "rename this button; clear it to go back to the issuer's label")
    static let designerAddActionKind = HelpEntry("designer.addActionKind", "Add button", "add a button of this kind to the banner")
    static let designerExtraKey = HelpEntry("designer.extraKey", "Extra key", "name of your own value; letters, digits, _ . and - only")
    static let designerExtraValue = HelpEntry("designer.extraValue", "Extra value", "the value sent to every action under this key")
    static let designerAddExtraValue = HelpEntry("designer.addExtraValue", "Add value", "add another extra key and value sent to every action")
    static let designerEditorLabel = HelpEntry("designer.editorLabel", "Button label", "the text shown on the banner button; tokens like {title} are filled in")
    static let designerEditorKind = HelpEntry("designer.editorKind", "Button action", "what pressing this button does: open a link, run a script and so on")
    static let designerEditorStyle = HelpEntry("designer.editorStyle", "Button style", "default, destructive or quiet look for this button")
    static let designerEditorId = HelpEntry("designer.editorId", "Button id", "the name rules and button cells use to refer to this button")
    static let designerEditorAdvanced = HelpEntry("designer.editorAdvanced", "Advanced", "show the button id and other low-level settings")
    static let designerEditorCancel = HelpEntry("designer.editorCancel", "Cancel", "close without keeping your changes", "\u{238B}")
    static let designerEditorSave = HelpEntry("designer.editorSave", "Save button", "keep this button and close the editor", "\u{21A9}")
    static let designerActionUrl = HelpEntry("designer.actionUrl", "Link", "the address to open in your browser; only http, https and mailto links open")
    static let designerActionCommand = HelpEntry("designer.actionCommand", "Shell command", "command run with zsh; the notification arrives as JSON on stdin")
    static let designerCallbackPayload = HelpEntry("designer.callbackPayload", "Callback payload", "JSON sent back to the issuer when this button is pressed")
    static let designerSnoozeStepper = HelpEntry("designer.snoozeStepper", "Snooze minutes", "how long the notification is snoozed, in minutes")
    static let designerSnoozePreset = HelpEntry("designer.snoozePreset", "Snooze preset", "set the snooze to this length")
    static let designerScriptName = HelpEntry("designer.scriptName", "Script file", "name of a file in Herald's scripts folder")
    static let designerScriptMenu = HelpEntry("designer.scriptMenu", "Choose script", "pick a script from the scripts folder")
    static let designerOpenScripts = HelpEntry("designer.openScripts", "Open scripts folder", "show the scripts folder in Finder")
    static let designerShortcutName = HelpEntry("designer.shortcutName", "Shortcut name", "name of the Apple Shortcut to run")
    static let designerReloadShortcuts = HelpEntry("designer.reloadShortcuts", "Reload Shortcuts", "read the list of Shortcuts again")
    static let designerShortcutInput = HelpEntry("designer.shortcutInput", "Shortcut input", "hand the Shortcut the whole notification as JSON, or your own text")
    static let designerShortcutText = HelpEntry("designer.shortcutText", "Shortcut text", "the text handed to the Shortcut; tokens like {title} are filled in")
    static let designerOpenShortcuts = HelpEntry("designer.openShortcuts", "Open Shortcuts", "launch the Shortcuts app")
    static let designerSearchShortcuts = HelpEntry("designer.searchShortcuts", "Search Shortcuts", "filter the list of Shortcuts by name")
    static let designerInsertField = HelpEntry("designer.insertField", "Insert field", "add a field token such as {title} from the notification")
    static let designerFieldBinding = HelpEntry("designer.fieldBinding", "Field binding", "type text, or insert fields like {title} that are filled from the notification")
    static let designerColorMode = HelpEntry("designer.colorMode", "Color", "follow the style, use a named color, or pick a custom one")
    static let designerColorWell = HelpEntry("designer.colorWell", "Custom color", "pick the color from the color panel")
    static let designerColorHex = HelpEntry("designer.colorHex", "Hex color", "type the color as #RRGGBB")
    static let designerAlignPoint = HelpEntry("designer.alignPoint", "Alignment point", "place the content at this point of the cell")
    static let designerMergeSlots = HelpEntry("designer.mergeSlots", "Merge slots", "join the selected slots into one cell you can put a component in")
    static let designerAddComponent = HelpEntry("designer.addComponent", "Add component", "put this component in the selected slot")
    static let designerComponentType = HelpEntry("designer.componentType", "Component type", "switch this cell to another kind of component")
    static let designerCellRow = HelpEntry("designer.cellRow", "Row", "move this cell to another row")
    static let designerCellColumn = HelpEntry("designer.cellColumn", "Column", "move this cell to another column")
    static let designerRowSpan = HelpEntry("designer.rowSpan", "Row span", "how many rows this cell covers; it can only grow into empty slots")
    static let designerColSpan = HelpEntry("designer.colSpan", "Column span", "how many columns this cell covers; it can only grow into empty slots")
    static let designerCellPadding = HelpEntry("designer.cellPadding", "Cell padding", "space inside this cell, in points")
    static let designerSplitCell = HelpEntry("designer.splitCell", "Split cell", "cut this merged cell back into single slots")
    static let designerDuplicateCell = HelpEntry("designer.duplicateCell", "Duplicate cell", "copy this component into the next free slot")
    static let designerDeleteCell = HelpEntry("designer.deleteCell", "Delete cell", "remove this component from the template")
    static let designerEmptyBehavior = HelpEntry("designer.emptyBehavior", "When empty", "what this component does when the notification has no value for it")
    static let designerPreviewWithout = HelpEntry("designer.previewWithout", "Preview without fields", "preview the banner as if these fields were missing")
    static let designerTextStyle = HelpEntry("designer.textStyle", "Text style", "choose the type style of this text")
    static let designerMaxLines = HelpEntry("designer.maxLines", "Line limit", "most lines to show; empty uses the style’s limit")
    static let designerFontSize = HelpEntry("designer.fontSize", "Font size", "x")
    static let designerFontWeight = HelpEntry("designer.fontWeight", "Font weight", "choose the weight of this text, or follow the style")
    static let designerTextAlignment = HelpEntry("designer.textAlignment", "Text alignment", "align the text inside its cell, or follow the cell")
    static let designerMarkdown = HelpEntry("designer.markdown", "Links and markdown", "turn markdown and links in the text on or off")
    static let designerImageFit = HelpEntry("designer.imageFit", "Image fit", "fit inside the cell, fill it, or cover it while cropping")
    static let designerCornerRadius = HelpEntry("designer.cornerRadius", "Corner radius", "how round the corners are, in points")
    static let designerAspectRatio = HelpEntry("designer.aspectRatio", "Aspect ratio", "width divided by height; empty keeps the image’s own")
    static let designerHeight = HelpEntry("designer.height", "Height", "x")
    static let designerIconSize = HelpEntry("designer.iconSize", "Icon size", "size of the issuer icon, in points")
    static let designerIconShape = HelpEntry("designer.iconShape", "Icon shape", "rounded square or circle")
    static let designerIconCorners = HelpEntry("designer.iconCorners", "Icon corners", "corner radius in points; empty picks one automatically")
    static let designerTimeFormat = HelpEntry("designer.timeFormat", "Time format", "show the clock time or a relative time such as 3 min ago")
    static let designerTimeStyle = HelpEntry("designer.timeStyle", "Time style", "choose the type style of the time")
    static let designerButtonStyle = HelpEntry("designer.buttonStyle", "Button style", "default, destructive or quiet look; empty uses the action’s own")
    static let designerActionsSource = HelpEntry("designer.actionsSource", "Buttons shown", "show the issuer’s buttons, yours, or both")
    static let designerActionsLayout = HelpEntry("designer.actionsLayout", "Buttons layout", "wrap, one row, or a vertical stack")
    static let designerMaxButtons = HelpEntry("designer.maxButtons", "Most buttons", "most buttons shown; empty shows all")
    static let designerEditButtons = HelpEntry("designer.editButtons", "Edit the buttons", "switch to the Actions tab")
    static let designerIconButtonSize = HelpEntry("designer.iconButtonSize", "Icon button size", "size in points; empty uses the default")
    static let designerIconButtonTooltip = HelpEntry("designer.iconButtonTooltip", "Button tooltip", "text shown when someone hovers the button on the banner")
    static let designerRiveAsset = HelpEntry("designer.riveAsset", "Animation file", "choose a declared Rive file, or enter your own")
    static let designerRivePath = HelpEntry("designer.rivePath", "Animation path", "a .riv file name in the assets folder, or a full path")
    static let designerRiveStored = HelpEntry("designer.riveStored", "Stored animations", "pick a file you added to this issuer’s assets folder")
    static let designerRiveArtboard = HelpEntry("designer.riveArtboard", "Artboard", "which artboard of the file to show")
    static let designerRiveArtboardName = HelpEntry("designer.riveArtboardName", "Artboard name", "name of the artboard to show; empty uses the default")
    static let designerRiveMachine = HelpEntry("designer.riveMachine", "State machine", "which state machine runs")
    static let designerRiveMachineName = HelpEntry("designer.riveMachineName", "State machine name", "name of the state machine to run; empty uses the default")
    static let designerRiveLoop = HelpEntry("designer.riveLoop", "Loop", "loop the animation or play it once")
    static let designerRiveRatio = HelpEntry("designer.riveRatio", "Aspect ratio", "width divided by height; empty uses the artboard’s own")
    static let designerThickness = HelpEntry("designer.thickness", "Thickness", "height of the bar in points")
    static let designerRiveDetails = HelpEntry("designer.riveDetails", "File contents", "show the artboards, state machines and inputs in this file")
    static let designerRiveInputName = HelpEntry("designer.riveInputName", "Input name", "name of a state machine input to drive")
    static let designerRiveInputValue = HelpEntry("designer.riveInputValue", "Input value", "the value to give the input; use a field like {count} or a pointer keyword")
    static let designerRiveInputPick = HelpEntry("designer.riveInputPick", "Pick input value", "insert a pointer keyword or a field")
    static let designerRemoveRiveInput = HelpEntry("designer.removeRiveInput", "Remove input", "stop driving this input")
    static let designerAddRiveInput = HelpEntry("designer.addRiveInput", "Add input", "drive another state machine input")
    static let designerRiveInputsFromFile = HelpEntry("designer.riveInputsFromFile", "Inputs from file", "add an input the Rive file declares")
    static let designerSlotMode = HelpEntry("designer.slotMode", "Click action", "what happens on click: nothing, a listed button, or an action of its own")
    static let designerSlotAction = HelpEntry("designer.slotAction", "Listed action", "which issuer or custom button this runs")
    static let designerEditSlotAction = HelpEntry("designer.editSlotAction", "Edit action", "change what this click action does")
    static let designerTemplateName = HelpEntry("designer.templateName", "Template name", "the name notifications use to pick this template")
    static let designerReloadTemplate = HelpEntry("designer.reloadTemplate", "Reload from disk", "drop your edits and load the version that changed on disk")
    static let designerCollapseEmpty = HelpEntry("designer.collapseEmpty", "Empty fields", "collapse empty fields, or leave their space in place")
    static let designerBodyLines = HelpEntry("designer.bodyLines", "Body lines", "line limit for body text that sets none of its own")
    static let designerGridWidth = HelpEntry("designer.gridWidth", "Banner width", "width of the banner in points")
    static let designerGridGap = HelpEntry("designer.gridGap", "Grid gap", "space between cells, in points")
    static let designerGridPadding = HelpEntry("designer.gridPadding", "Grid padding", "space around the grid, in points")
    static let designerAddColumn = HelpEntry("designer.addColumn", "Add column", "add a column at the right of the grid")
    static let designerAddRow = HelpEntry("designer.addRow", "Add row", "add a row at the bottom of the grid")
    static let designerTrackSize = HelpEntry("designer.trackSize", "Track size", "Auto fits the content, Fill shares what is left, Points is exact")
    static let designerRemoveTrack = HelpEntry("designer.removeTrack", "Remove track", "delete this row or column from the grid")
}

extension HeraldHelpCatalog {
    static let designer: [HelpEntry] = [
        .designerPreviewDivider,
        .designerModePicker,
        .designerImportBundle,
        .designerExportBundle,
        .designerUndo,
        .designerRedo,
        .designerMerge,
        .designerSplit,
        .designerDuplicateComponent,
        .designerDeleteComponent,
        .designerZoom,
        .designerAppearance,
        .designerAbsentFields,
        .designerIssues,
        .designerSendTest,
        .designerSave,
        .designerFieldPresent,
        .designerAllPresent,
        .designerZoomOut,
        .designerZoomSlider,
        .designerZoomIn,
        .designerZoomReset,
        .designerPreviewSource,
        .designerIssueRow,
        .designerIssuerPicker,
        .designerDuplicateTemplate,
        .designerNewTemplate,
        .designerDeleteTemplate,
        .designerSetDefault,
        .designerOldLayoutBadge,
        .designerDefaultBadge,
        .designerUnsavedDot,
        .designerCustomField,
        .designerAddCustomField,
        .designerAddAction,
        .designerAddAsset,
        .designerRemoveAsset,
        .designerRemoveExtraValue,
        .designerRemoveTemplateAction,
        .designerEditTemplateAction,
        .designerResetIssuerAction,
        .designerMoveActionUp,
        .designerMoveActionDown,
        .designerHideAction,
        .designerActionStyle,
        .designerActionLabel,
        .designerAddActionKind,
        .designerExtraKey,
        .designerExtraValue,
        .designerAddExtraValue,
        .designerEditorLabel,
        .designerEditorKind,
        .designerEditorStyle,
        .designerEditorId,
        .designerEditorAdvanced,
        .designerEditorCancel,
        .designerEditorSave,
        .designerActionUrl,
        .designerActionCommand,
        .designerCallbackPayload,
        .designerSnoozeStepper,
        .designerSnoozePreset,
        .designerScriptName,
        .designerScriptMenu,
        .designerOpenScripts,
        .designerShortcutName,
        .designerReloadShortcuts,
        .designerShortcutInput,
        .designerShortcutText,
        .designerOpenShortcuts,
        .designerSearchShortcuts,
        .designerInsertField,
        .designerFieldBinding,
        .designerColorMode,
        .designerColorWell,
        .designerColorHex,
        .designerAlignPoint,
        .designerMergeSlots,
        .designerAddComponent,
        .designerComponentType,
        .designerCellRow,
        .designerCellColumn,
        .designerRowSpan,
        .designerColSpan,
        .designerCellPadding,
        .designerSplitCell,
        .designerDuplicateCell,
        .designerDeleteCell,
        .designerEmptyBehavior,
        .designerPreviewWithout,
        .designerTextStyle,
        .designerMaxLines,
        .designerFontSize,
        .designerFontWeight,
        .designerTextAlignment,
        .designerMarkdown,
        .designerImageFit,
        .designerCornerRadius,
        .designerAspectRatio,
        .designerHeight,
        .designerIconSize,
        .designerIconShape,
        .designerIconCorners,
        .designerTimeFormat,
        .designerTimeStyle,
        .designerButtonStyle,
        .designerActionsSource,
        .designerActionsLayout,
        .designerMaxButtons,
        .designerEditButtons,
        .designerIconButtonSize,
        .designerIconButtonTooltip,
        .designerRiveAsset,
        .designerRivePath,
        .designerRiveStored,
        .designerRiveArtboard,
        .designerRiveArtboardName,
        .designerRiveMachine,
        .designerRiveMachineName,
        .designerRiveLoop,
        .designerRiveRatio,
        .designerThickness,
        .designerRiveDetails,
        .designerRiveInputName,
        .designerRiveInputValue,
        .designerRiveInputPick,
        .designerRemoveRiveInput,
        .designerAddRiveInput,
        .designerRiveInputsFromFile,
        .designerSlotMode,
        .designerSlotAction,
        .designerEditSlotAction,
        .designerTemplateName,
        .designerReloadTemplate,
        .designerCollapseEmpty,
        .designerBodyLines,
        .designerGridWidth,
        .designerGridGap,
        .designerGridPadding,
        .designerAddColumn,
        .designerAddRow,
        .designerTrackSize,
        .designerRemoveTrack,
    ]
}
