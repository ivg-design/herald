import Foundation

extension HelpEntry {
    // Designer controls: id, name, detail, shortcut.
    static let designerPreviewDivider = HelpEntry("designer.previewDivider", "Resize preview", "The divider between the editor and the live preview, which sets how much room each gets")
    static let designerModePicker = HelpEntry("designer.modePicker", "Mode", "Switches between designing a saved template and composing a one-off notification")
    static let designerImportBundle = HelpEntry("designer.importBundle", "Import", "Adds a template bundle (.heraldtemplate) together with the animations it carries")
    static let designerExportBundle = HelpEntry("designer.exportBundle", "Export", "Packs this template and the animations it plays into a shareable .heraldtemplate bundle")
    static let designerUndo = HelpEntry("designer.undo", "Undo", "Reverses the latest edit to the template", "\u{2318}Z")
    static let designerRedo = HelpEntry("designer.redo", "Redo", "Restores the edit that was just undone", "\u{21E7}\u{2318}Z")
    static let designerMerge = HelpEntry("designer.merge", "Merge cells", "Join the selected cells into one slot spanning rows and columns")
    static let designerSplit = HelpEntry("designer.split", "Split cell", "Turns a merged cell back into the individual slots it covered")
    static let designerDuplicateComponent = HelpEntry("designer.duplicateComponent", "Duplicate component", "A copy of the chosen component, with all its settings, in the next free slot", "\u{2318}D")
    static let designerDeleteComponent = HelpEntry("designer.deleteComponent", "Delete component", "Removes the chosen component from the template and empties its slot", "\u{2318}\u{232B}")
    static let designerZoom = HelpEntry("designer.zoom", "Zoom", "The scale of the current pane, from 50% to 300%, with a slider and a reset", "\u{2318}+ \u{2318}\u{2212} \u{2318}0")
    static let designerAppearance = HelpEntry("designer.appearance", "Preview appearance", "Whether the live preview draws the banner in light or dark appearance")
    static let designerAbsentFields = HelpEntry("designer.absentFields", "Absent fields", "Fields treated as missing in the preview, to show how the template copes without them")
    static let designerIssues = HelpEntry("designer.issues", "Template problems", "Problems the checker found in this template, each tied to the cell it concerns")
    static let designerSendTest = HelpEntry("designer.sendTest", "Send test", "Shows this banner on screen through Herald using the preview data")
    static let designerSave = HelpEntry("designer.save", "Save template", "Writes the template to disk so notifications can name it", "\u{2318}S")
    static let designerFieldPresent = HelpEntry("designer.fieldPresent", "Field present", "Whether this field counts as present in the preview; clearing it previews the banner without the field")
    static let designerAllPresent = HelpEntry("designer.allPresent", "All present", "Marks every field as present again in the preview")
    static let designerZoomOut = HelpEntry("designer.zoomOut", "Zoom out", "Shrinks the pane by one zoom step", "\u{2318}\u{2212}")
    static let designerZoomSlider = HelpEntry("designer.zoomSlider", "Zoom level", "The pane's zoom level, from 50% to 300%")
    static let designerZoomIn = HelpEntry("designer.zoomIn", "Zoom in", "Enlarges the pane by one zoom step", "\u{2318}+")
    static let designerZoomReset = HelpEntry("designer.zoomReset", "Reset zoom", "Returns the pane to 100% zoom", "\u{2318}0")
    static let designerPreviewSource = HelpEntry("designer.previewSource", "Preview data", "Which data the preview shows: Sample uses the manifest's example values, Last real uses your newest actual notification")
    static let designerIssueRow = HelpEntry("designer.issueRow", "Problem", "A problem found in the template, pointing at the cell it is about")
    static let designerIssuerPicker = HelpEntry("designer.issuerPicker", "Issuer", "The app whose notifications and templates you are designing")
    static let designerDuplicateTemplate = HelpEntry("designer.duplicateTemplate", "Duplicate template", "A copy of this template, including unsaved edits, saved under a new name")
    static let designerNewTemplate = HelpEntry("designer.newTemplate", "New template", "A blank grid, or one built from a standard layout")
    static let designerDeleteTemplate = HelpEntry("designer.deleteTemplate", "Delete template", "Removes the chosen template from this issuer after confirmation")
    static let designerSetDefault = HelpEntry("designer.setDefault", "Issuer default", "Makes this the template used by this issuer's notifications that name none")
    static let designerOldLayoutBadge = HelpEntry("designer.oldLayoutBadge", "Old layout", "Marks a template in the v1 layout, which opens converted to a grid")
    static let designerDefaultBadge = HelpEntry("designer.defaultBadge", "Default template", "Marks the template used when a notification names none")
    static let designerUnsavedDot = HelpEntry("designer.unsavedDot", "Unsaved changes", "Marks a template with edits that are not saved yet")
    static let designerCustomField = HelpEntry("designer.customField", "Custom field", "A key the issuer may send in its metadata that its manifest does not declare")
    static let designerAddCustomField = HelpEntry("designer.addCustomField", "Add custom field", "Adds the typed key to the field list so it can be bound")
    static let designerAddAction = HelpEntry("designer.addAction", "Add action", "A banner button of any kind: a shortcut, script, command, link, callback, snooze or dismiss")
    static let designerAddAsset = HelpEntry("designer.addAsset", "Add animation", "A .riv animation copied into this issuer's assets folder")
    static let designerRemoveAsset = HelpEntry("designer.removeAsset", "Remove animation", "Deletes this .riv file from the issuer's assets folder")
    static let designerRemoveExtraValue = HelpEntry("designer.removeExtraValue", "Remove value", "Deletes this extra key and its value")
    static let designerRemoveTemplateAction = HelpEntry("designer.removeTemplateAction", "Remove button", "Deletes a button you added to this template")
    static let designerEditTemplateAction = HelpEntry("designer.editTemplateAction", "Edit button", "Opens this button's label, action and look for changes")
    static let designerResetIssuerAction = HelpEntry("designer.resetIssuerAction", "Reset button", "Restores the button to exactly what the issuer sent, undoing renames, restyling and hiding")
    static let designerMoveActionUp = HelpEntry("designer.moveActionUp", "Move button up", "Moves this button earlier in the banner's row of buttons")
    static let designerMoveActionDown = HelpEntry("designer.moveActionDown", "Move button down", "Moves this button later in the banner's row of buttons")
    static let designerHideAction = HelpEntry("designer.hideAction", "Show or hide button", "Whether this issuer button appears on the banner")
    static let designerActionStyle = HelpEntry("designer.actionStyle", "Button style", "This button's look: default, destructive or cancel")
    static let designerActionLabel = HelpEntry("designer.actionLabel", "Button label", "The text on this button; leaving it empty falls back to the issuer's label")
    static let designerAddActionKind = HelpEntry("designer.addActionKind", "Add button", "A new button of this kind on the banner")
    static let designerExtraKey = HelpEntry("designer.extraKey", "Extra key", "The name of your own fixed value; letters, digits, _ . and - are allowed")
    static let designerExtraValue = HelpEntry("designer.extraValue", "Extra value", "The value sent to every action under this key")
    static let designerAddExtraValue = HelpEntry("designer.addExtraValue", "Add value", "Another extra key and value sent to every action")
    static let designerEditorLabel = HelpEntry("designer.editorLabel", "Button label", "The text shown on the banner button; tokens like {title} are filled from the notification")
    static let designerEditorKind = HelpEntry("designer.editorKind", "Button action", "What the button does when used: open a link, run a script and so on")
    static let designerEditorStyle = HelpEntry("designer.editorStyle", "Button style", "The button's look (normal, prominent, destructive or quiet); destructive ones ask before running")
    static let designerEditorId = HelpEntry("designer.editorId", "Button id", "The name that rules and button cells use to refer to this button")
    static let designerEditorAdvanced = HelpEntry("designer.editorAdvanced", "Advanced", "Low-level settings of this button, including its id")
    static let designerEditorCancel = HelpEntry("designer.editorCancel", "Cancel", "Closes the editor and discards your changes", "\u{238B}")
    static let designerEditorSave = HelpEntry("designer.editorSave", "Save button", "Keeps this button and closes the editor", "\u{21A9}")
    static let designerActionUrl = HelpEntry("designer.actionUrl", "Link", "The address opened in your browser; only http, https and mailto links open")
    static let designerActionCommand = HelpEntry("designer.actionCommand", "Shell command", "A command run with zsh that receives the notification as JSON on stdin")
    static let designerCallbackPayload = HelpEntry("designer.callbackPayload", "Callback payload", "JSON sent back to the issuer when this button is used")
    static let designerSnoozeStepper = HelpEntry("designer.snoozeStepper", "Snooze minutes", "How many minutes the notification is postponed")
    static let designerSnoozePreset = HelpEntry("designer.snoozePreset", "Snooze preset", "A ready-made snooze length")
    static let designerScriptName = HelpEntry("designer.scriptName", "Script file", "A file in Herald's scripts folder that the button runs")
    static let designerScriptMenu = HelpEntry("designer.scriptMenu", "Choose script", "The scripts found in the scripts folder, listed for choosing one")
    static let designerOpenScripts = HelpEntry("designer.openScripts", "Open scripts folder", "Herald's scripts folder, shown in Finder")
    static let designerShortcutName = HelpEntry("designer.shortcutName", "Shortcut name", "The Apple Shortcut this button runs")
    static let designerReloadShortcuts = HelpEntry("designer.reloadShortcuts", "Reload Shortcuts", "Rereads the list of Shortcuts installed on this Mac")
    static let designerShortcutInput = HelpEntry("designer.shortcutInput", "Shortcut input", "What the Shortcut receives: the whole notification as JSON, or text of your own")
    static let designerShortcutText = HelpEntry("designer.shortcutText", "Shortcut text", "The text handed to the Shortcut; tokens like {title} are filled in")
    static let designerOpenShortcuts = HelpEntry("designer.openShortcuts", "Open Shortcuts", "The Shortcuts app, launched")
    static let designerSearchShortcuts = HelpEntry("designer.searchShortcuts", "Search Shortcuts", "Narrows the list of Shortcuts to names matching the text")
    static let designerInsertField = HelpEntry("designer.insertField", "Insert field", "A token such as {title} that is filled from the notification when shown")
    static let designerFieldBinding = HelpEntry("designer.fieldBinding", "Field binding", "Fixed text, or tokens like {title} filled from the notification")
    static let designerRichEditor = HelpEntry("designer.richEditor", "Text editor", "The text with its markup visible: **bold**, *italic*, `mono`, __underline__, ~~strike~~, one line per line")
    static let designerRichBold = HelpEntry("designer.richBold", "Bold", "Bold weight for the selected text")
    static let designerRichItalic = HelpEntry("designer.richItalic", "Italic", "Italic for the selected text")
    static let designerRichMono = HelpEntry("designer.richMono", "Monospace", "A monospaced font for the selected text")
    static let designerRichUnderline = HelpEntry("designer.richUnderline", "Underline", "An underline for the selected text")
    static let designerRichStrike = HelpEntry("designer.richStrike", "Strikethrough", "A line through the selected text")
    static let designerRichSizeUp = HelpEntry("designer.richSizeUp", "Larger", "The selected text one point bigger than it is now")
    static let designerRichSizeDown = HelpEntry("designer.richSizeDown", "Smaller", "The selected text one point smaller than it is now")
    static let designerRichColor = HelpEntry("designer.richColor", "Text color", "A color for the selected text only")
    static let designerRichLineAlign = HelpEntry("designer.richLineAlign", "Line alignment", "How the line holding the cursor is aligned; Cell follows the component")
    static let designerColorMode = HelpEntry("designer.colorMode", "Color", "Where the color comes from: the style, a named color or a custom one")
    static let designerColorWell = HelpEntry("designer.colorWell", "Custom color", "A custom color chosen in the system color panel")
    static let designerColorHex = HelpEntry("designer.colorHex", "Hex color", "The color written as #RRGGBB")
    static let designerAlignPoint = HelpEntry("designer.alignPoint", "Alignment point", "The point of the cell where the content sits")
    static let designerMergeSlots = HelpEntry("designer.mergeSlots", "Merge cells", "Combines the chosen empty slots into one cell that can hold a component")
    static let designerAddComponent = HelpEntry("designer.addComponent", "Add component", "The chosen component, placed in the current slot")
    static let designerComponentType = HelpEntry("designer.componentType", "Component type", "Changes this cell to another kind of component")
    static let designerCellRow = HelpEntry("designer.cellRow", "Row", "The grid row this cell starts in")
    static let designerCellColumn = HelpEntry("designer.cellColumn", "Column", "The grid column this cell starts in")
    static let designerRowSpan = HelpEntry("designer.rowSpan", "Row span", "How many rows this cell covers; it can only grow into empty slots")
    static let designerColSpan = HelpEntry("designer.colSpan", "Column span", "How many columns this cell covers; it can only grow into empty slots")
    static let designerCellPadding = HelpEntry("designer.cellPadding", "Cell padding", "Space between the cell's edge and its content, in points")
    static let designerSplitCell = HelpEntry("designer.splitCell", "Split cell", "Breaks this cell's span apart so each slot can hold its own component")
    static let designerDuplicateCell = HelpEntry("designer.duplicateCell", "Duplicate cell", "The same component and settings again, placed in the next empty slot of the grid")
    static let designerDeleteCell = HelpEntry("designer.deleteCell", "Delete cell", "Removes this cell's component and leaves its slot empty")
    static let designerEmptyBehavior = HelpEntry("designer.emptyBehavior", "When empty", "What this component does when the notification has no value for it: collapse its space or keep it")
    static let designerPreviewWithout = HelpEntry("designer.previewWithout", "Preview without fields", "Previews the banner as if these fields were missing")
    static let designerTextStyle = HelpEntry("designer.textStyle", "Text style", "The type style of this text, which sets its size and weight")
    static let designerMaxLines = HelpEntry("designer.maxLines", "Line limit", "The most lines shown; empty uses the style's limit")
    static let designerFontSize = HelpEntry("designer.fontSize", "Font size", "Text size in points; empty uses the style's size")
    static let designerFontWeight = HelpEntry("designer.fontWeight", "Font weight", "The weight of this text, or the style's own weight")
    static let designerTextAlignment = HelpEntry("designer.textAlignment", "Text alignment", "How the text sits inside its cell, or the cell's own alignment")
    static let designerMarkdown = HelpEntry("designer.markdown", "Links and markdown", "Whether markdown formatting and links in the text are rendered")
    static let designerImageFit = HelpEntry("designer.imageFit", "Image fit", "How the image fills its cell: fit inside, fill it, or cover it with cropping")
    static let designerCornerRadius = HelpEntry("designer.cornerRadius", "Corner radius", "How round the corners are, in points")
    static let designerAspectRatio = HelpEntry("designer.aspectRatio", "Aspect ratio", "Width divided by height of the image; empty keeps the image's own")
    static let designerHeight = HelpEntry("designer.height", "Height", "A fixed height in points; empty sizes to the content")
    static let designerIconSize = HelpEntry("designer.iconSize", "Icon size", "Size of the issuer's app icon, in points")
    static let designerIconShape = HelpEntry("designer.iconShape", "Icon shape", "Whether the app icon is a rounded square or a circle")
    static let designerIconCorners = HelpEntry("designer.iconCorners", "Icon corners", "The icon's corner radius in points; empty picks one automatically")
    static let designerTimeFormat = HelpEntry("designer.timeFormat", "Time format", "Whether the time shows as a clock time or as a relative time such as 3 min ago")
    static let designerTimeStyle = HelpEntry("designer.timeStyle", "Time style", "The type style of the time text")
    static let designerButtonStyle = HelpEntry("designer.buttonStyle", "Button style", "The look of this button cell (normal, prominent, destructive or quiet); empty uses the action's own")
    static let designerActionsSource = HelpEntry("designer.actionsSource", "Buttons shown", "Whose buttons the Actions cell shows: the issuer's, yours, or both")
    static let designerActionsLayout = HelpEntry("designer.actionsLayout", "Buttons layout", "How the buttons are arranged: wrapped, in one row or stacked vertically")
    static let designerMaxButtons = HelpEntry("designer.maxButtons", "Most buttons", "The most buttons shown; empty shows all")
    static let designerEditButtons = HelpEntry("designer.editButtons", "Edit the buttons", "The Actions tab, where the issuer's buttons and your own are edited")
    static let designerIconButtonSize = HelpEntry("designer.iconButtonSize", "Icon button size", "Size of the icon button in points; empty uses the default")
    static let designerIconButtonTooltip = HelpEntry("designer.iconButtonTooltip", "Button tooltip", "The text that appears when someone hovers the button on the banner")
    static let designerRiveAsset = HelpEntry("designer.riveAsset", "Animation file", "The Rive animation file played, taken from the declared list or entered yourself")
    static let designerRivePath = HelpEntry("designer.rivePath", "Animation path", "A .riv file name in the assets folder, or a full path")
    static let designerRiveStored = HelpEntry("designer.riveStored", "Stored animations", "A Rive file already added to this issuer's assets folder")
    static let designerRiveArtboard = HelpEntry("designer.riveArtboard", "Artboard", "The artboard of the Rive file that is shown")
    static let designerRiveArtboardName = HelpEntry("designer.riveArtboardName", "Artboard name", "Name of the artboard to show; empty uses the file's default")
    static let designerRiveMachine = HelpEntry("designer.riveMachine", "State machine", "The state machine that drives the animation")
    static let designerRiveMachineName = HelpEntry("designer.riveMachineName", "State machine name", "Name of the state machine to run; empty uses the default")
    static let designerRiveLoop = HelpEntry("designer.riveLoop", "Loop", "Whether the animation repeats or plays once")
    static let designerRiveRatio = HelpEntry("designer.riveRatio", "Aspect ratio", "Width divided by height of the animation; empty uses the artboard's own")
    static let designerThickness = HelpEntry("designer.thickness", "Thickness", "Height of the progress bar, in points")
    static let designerRiveDetails = HelpEntry("designer.riveDetails", "File contents", "The artboards, state machines and inputs this Rive file declares")
    static let designerRiveInputName = HelpEntry("designer.riveInputName", "Input name", "The state machine input this row drives")
    static let designerRiveInputValue = HelpEntry("designer.riveInputValue", "Input value", "The value given to the input: a field like {count} or a pointer keyword")
    static let designerRiveInputPick = HelpEntry("designer.riveInputPick", "Pick input value", "A pointer keyword or field to use as the input's value")
    static let designerRemoveRiveInput = HelpEntry("designer.removeRiveInput", "Remove input", "Stops driving this state machine input")
    static let designerAddRiveInput = HelpEntry("designer.addRiveInput", "Add input", "Another state machine input driven by the banner")
    static let designerRiveInputsFromFile = HelpEntry("designer.riveInputsFromFile", "Inputs from file", "An input the Rive file itself declares, added to the list")
    static let designerSlotMode = HelpEntry("designer.slotMode", "Cell action", "What happens when the reader uses this cell: nothing, a listed button, or an action of its own")
    static let designerSlotAction = HelpEntry("designer.slotAction", "Listed action", "The issuer or custom button this cell runs")
    static let designerEditSlotAction = HelpEntry("designer.editSlotAction", "Edit action", "Opens the action this cell runs for changes")
    static let designerTemplateName = HelpEntry("designer.templateName", "Template name", "The name notifications use to ask for this template")
    static let designerReloadTemplate = HelpEntry("designer.reloadTemplate", "Reload from disk", "Discards your edits and loads the version that changed on disk")
    static let designerCollapseEmpty = HelpEntry("designer.collapseEmpty", "Empty fields", "Collapse removes an empty field and closes its row or column; Leave in place keeps the space so every banner has the same layout")
    static let designerBodyLines = HelpEntry("designer.bodyLines", "Body lines", "Line limit for body text that sets none of its own")
    static let designerGridWidth = HelpEntry("designer.gridWidth", "Banner width", "Width of the whole banner in points")
    static let designerGridGap = HelpEntry("designer.gridGap", "Grid gap", "Space between cells, in points")
    static let designerGridPadding = HelpEntry("designer.gridPadding", "Grid padding", "Space around the grid, in points")
    static let designerAddColumn = HelpEntry("designer.addColumn", "Add column", "A new column at the right edge of the grid")
    static let designerAddRow = HelpEntry("designer.addRow", "Add row", "A new row at the bottom of the grid")
    static let designerTrackSize = HelpEntry("designer.trackSize", "Track size", "How a row or column is sized: Auto fits its content, Fill shares what is left, Points is exact")
    static let designerRemoveTrack = HelpEntry("designer.removeTrack", "Remove track", "Deletes this row or column from the grid")
    static let designerCheckRow = HelpEntry("designer.checkRow", "Problem", "A check result for the grid that points at the cell it concerns")
    static let designerTrackPoints = HelpEntry("designer.trackPoints", "Track points", "The exact size of this row or column in points")
    static let designerResizeCell = HelpEntry("designer.resizeCell", "Resize cell", "The handle that grows or shrinks the rows and columns this cell spans")
    static let designerTrackMenu = HelpEntry("designer.trackMenu", "Row or column size", "The sizing of this row or column: Auto, Fill or a fixed size")
    static let designerTrackHandle = HelpEntry("designer.trackHandle", "Resize track", "The edge that sets this row or column's size; resetting returns it to Auto")
    static let designerPickSymbol = HelpEntry("designer.pickSymbol", "Pick symbol", "An SF Symbol from those on this Mac, applied to this component")
    static let designerRemoveSymbol = HelpEntry("designer.removeSymbol", "Remove symbol", "Takes the SF Symbol off this component")
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
        .designerRichEditor,
        .designerRichBold,
        .designerRichItalic,
        .designerRichMono,
        .designerRichUnderline,
        .designerRichStrike,
        .designerRichSizeUp,
        .designerRichSizeDown,
        .designerRichColor,
        .designerRichLineAlign,
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
        .designerCheckRow,
        .designerTrackPoints,
        .designerResizeCell,
        .designerTrackMenu,
        .designerTrackHandle,
        .designerPickSymbol,
        .designerRemoveSymbol,
    ]
}
