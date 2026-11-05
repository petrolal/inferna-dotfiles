import "../denon.bar/panels" as Motion
import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Glass (direction G-A · Swatches): preset tiles that preview each look over the
// current wallpaper, Windows/Texture sliders, and an "Unsaved changes · Update /
// Save as new" bar. 20 built-in looks plus your own, stored by control.py in
// ~/.config/inferna/glass-presets.json.
Panel {
  id: root
  moduleName: "denon.glass"
  ipcTarget: "denon.glass"
  manageIpc: false
  implicitWidth: icon.implicitWidth
  implicitHeight: icon.implicitHeight
  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property string helper: Quickshell.env("HOME") + "/.local/share/omarchy-glass/control.py"
  readonly property string wallpaper: "file://" + Quickshell.env("HOME") + "/.local/state/inferna/current/background"
  property var values: ({enabled: true})
  property var presets: []
  property string presetId: ""
  property var pending: ({})
  property bool loaded: false
  property int page: 0
  property int selectedRow: 1      // 0 switch · 1 presets · 2 tabs · 3..6 sliders · 7 actions
  property int stripCursor: 0
  property bool naming: false
  property string manageId: ""     // user preset whose Rename/Delete row is shown
  property bool renaming: false
  property int openCount: 0
  property string message: "Loading…"

  readonly property var lookKeys: ["active", "inactive", "browser_active", "browser_inactive", "size", "contrast", "brightness", "vibrancy"]
  readonly property var windows: [
    {key: "active", label: "Focused apps", min: 0.4, max: 1, step: 0.01},
    {key: "inactive", label: "Unfocused apps", min: 0.4, max: 1, step: 0.01},
    {key: "browser_active", label: "Focused browser", min: 0.4, max: 1, step: 0.01},
    {key: "browser_inactive", label: "Unfocused browser", min: 0.4, max: 1, step: 0.01}
  ]
  readonly property var texture: [
    {key: "size", label: "Blur strength", min: 1, max: 12, step: 1},
    {key: "contrast", label: "Backdrop contrast", min: 0.5, max: 1.5, step: 0.05},
    {key: "brightness", label: "Backdrop brightness", min: 0.6, max: 1.2, step: 0.02},
    {key: "vibrancy", label: "Backdrop color", min: 0, max: 0.5, step: 0.01}
  ]
  readonly property var controls: page === 0 ? windows : texture
  readonly property bool busy: writeProc.running || readProc.running

  readonly property var activePreset: {
    for (var i = 0; i < presets.length; i++) if (presets[i].id === presetId) return presets[i]
    return null
  }
  readonly property bool modified: {
    if (!loaded) return false
    if (!activePreset) return true
    for (var i = 0; i < lookKeys.length; i++) {
      var k = lookKeys[i]
      if (Math.abs(Number(values[k]) - Number(activePreset.values[k])) > 0.0015) return true
    }
    return false
  }
  readonly property var managed: {
    for (var i = 0; i < presets.length; i++) if (presets[i].id === manageId) return presets[i]
    return null
  }

  function alphaOf(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function fmt(key, v) { return key === "size" ? String(Math.round(v || 0)) : Math.round((v || 0) * 100) + "%" }

  function refresh() { if (!busy && Object.keys(pending).length === 0) readProc.running = true }
  function receive(text, saved) {
    try {
      const result = JSON.parse(text)
      values = Object.assign({}, result.values, pending)
      if (result.presets) presets = result.presets
      presetId = result.preset || result.values.preset || ""
      loaded = true
      message = result.ok ? (saved ? "Saved · applied to your desktop" : "") : result.error
      if (!result.ok) return
      var idx = indexOfPreset(presetId)
      if (idx >= 0) { stripCursor = idx; Qt.callLater(function() { strip.reveal(idx) }) }
    } catch (e) { message = "Could not read Glass settings." }
  }
  function indexOfPreset(id) {
    for (var i = 0; i < presets.length; i++) if (presets[i].id === id) return i
    return -1
  }
  function preview(key, value) { const v = Object.assign({}, values); v[key] = value; values = v }
  function save(key, value) {
    if (!loaded) return
    preview(key, value)
    const p = Object.assign({}, pending); p[key] = value; pending = p
    drain()
  }
  function drain() {
    if (busy || Object.keys(pending).length === 0) return
    const key = Object.keys(pending)[0], value = pending[key]
    const p = Object.assign({}, pending); delete p[key]; pending = p
    message = "Applying…"
    writeProc.command = ["python3", helper, "set", key, String(value)]
    writeProc.running = true
  }
  function run(args) {
    if (busy || Object.keys(pending).length) return false
    message = "Applying…"
    writeProc.command = ["python3", helper].concat(args)
    writeProc.running = true
    return true
  }
  function applyPreset(id) { manageId = ""; naming = false; run(["preset", id]) }
  function startNaming() { manageId = ""; naming = true; Qt.callLater(function() { nameField.text = ""; nameField.forceActiveFocus() }) }
  function finishNaming(name) {
    name = String(name || "").trim()
    if (!name) return
    if (renaming) run(["rename-preset", manageId, name])
    else run(["save-preset", name])
    naming = false; renaming = false; manageId = ""
    keyboard.forceActiveFocus()
  }
  function cancelNaming() { naming = false; renaming = false; keyboard.forceActiveFocus() }
  function startRename() {
    if (!managed) return
    renaming = true; naming = true
    Qt.callLater(function() { nameField.text = root.managed ? root.managed.name : ""; nameField.selectAll(); nameField.forceActiveFocus() })
  }

  function adjust(dx) {
    if (selectedRow === 1) { stripCursor = Math.max(0, Math.min(presets.length - 1, stripCursor + dx)); strip.reveal(stripCursor); return }
    if (selectedRow === 2) { page = dx > 0 ? 1 : 0; return }
    if (selectedRow < 3 || selectedRow > 6) return
    const c = controls[selectedRow - 3]
    save(c.key, Math.round(Math.max(c.min, Math.min(c.max, values[c.key] + dx * c.step)) * 1000) / 1000)
  }
  function activate() {
    if (selectedRow === 0) save("enabled", !values.enabled)
    else if (selectedRow === 1 && presets[stripCursor]) applyPreset(presets[stripCursor].id)
    else if (selectedRow === 2) page = page === 0 ? 1 : 0
    else if (selectedRow === 7 && modified) startNaming()
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { openCount++; naming = false; manageId = ""; refresh() }

  IpcHandler {
    target: "denon.glass"
    function open(): void { root.open(); root.refresh() }
    function close(): void { root.close() }
    function state(): string { return JSON.stringify({values: root.values, preset: root.presetId, modified: root.modified, presets: root.presets.length, loaded: root.loaded, message: root.message, busy: root.busy}) }
    function set(key: string, value: string): void { root.save(key, key === "enabled" ? value === "true" : Number(value)) }
    function tab(index: int): void { root.page = index === 1 ? 1 : 0 }
    function preset(id: string): void { root.applyPreset(id) }
    function savePreset(name: string): void { root.run(["save-preset", name]) }
    function naming(): void { root.startNaming() }
    function manage(id: string): void { root.manageId = id }
  }
  Process {
    id: readProc
    command: ["python3", root.helper, "state"]
    stdout: StdioCollector { onStreamFinished: root.receive(text, false) }
    onExited: Qt.callLater(root.drain)
  }
  Process {
    id: writeProc
    stdout: StdioCollector { onStreamFinished: root.receive(text, true) }
    onExited: Qt.callLater(root.drain)
  }
  BarIconButton {
    id: icon
    anchors.fill: parent
    bar: root.bar
    text: "◈"
    tooltipText: root.activePreset ? "Glass · " + root.activePreset.name + (root.modified ? " (edited)" : "") : "Glass · opacity, blur & backdrop"
    onPressed: if (!Motion.PanelMotion.commitHover(root)) root.toggle()
  }

  Motion.PopupPanel {
    id: popup
    anchorItem: icon
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyboard
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyboard
      anchors.fill: parent
      onCloseRequested: { if (root.naming) root.cancelNaming(); else if (root.manageId) root.manageId = ""; else root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy) root.selectedRow = Math.max(0, Math.min(root.modified ? 7 : 6, root.selectedRow + dy))
        else root.adjust(dx)
      }
      onActivateRequested: root.activate()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        // ---------- Header: title · active preset · on/off switch ----------
        Item {
          width: parent.width
          height: Math.max(headerText.implicitHeight, toggle.height)
          Column {
            id: headerText
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text { text: "Glass"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.title + 1; font.weight: Font.Bold }
            Text {
              text: !root.values.enabled ? "Off · apps are solid"
                : root.activePreset ? root.activePreset.name + (root.modified ? " · edited" : " · applied")
                : "Custom look"
              color: root.alphaOf(root.fg, 0.6); font.family: root.family; font.pixelSize: Style.font.caption + 1
            }
          }
          Rectangle {
            id: toggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(38); height: Style.space(22); radius: height / 2
            color: root.values.enabled ? root.accent : root.alphaOf(root.fg, 0.16)
            border.width: root.selectedRow === 0 ? 2 : 0
            border.color: root.alphaOf(root.fg, 0.7)
            Behavior on color { ColorAnimation { duration: 160 } }
            Rectangle {
              width: parent.height - Style.space(4); height: width; radius: width / 2
              y: Style.space(2)
              x: root.values.enabled ? parent.width - width - Style.space(2) : Style.space(2)
              color: "white"
              Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
            MouseArea {
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
              enabled: root.loaded && !root.busy
              onClicked: root.save("enabled", !root.values.enabled)
              onEntered: root.selectedRow = 0
            }
          }
        }

        // ---------- Preset swatches ----------
        Item {
          width: parent.width
          height: tileHeight + Style.space(22)
          readonly property real tileWidth: Style.space(76)
          readonly property real tileHeight: Style.space(54)

          SwatchFrame {
            id: addTile
            width: parent.tileWidth; height: parent.tileHeight
            label: "Save"
            dashed: true
            onClicked: root.startNaming()
            Text {
              anchors.centerIn: parent
              text: "+"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.title + 4; font.weight: Font.Light
            }
          }

          Flickable {
            id: strip
            x: addTile.width + Style.space(8)
            width: parent.width - x
            height: parent.height
            contentWidth: stripRow.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            function reveal(i) {
              var tw = parent.tileWidth + Style.space(8)
              var left = i * tw, right = left + parent.tileWidth
              if (left < contentX) contentX = left
              else if (right > contentX + width) contentX = right - width
            }
            Behavior on contentX { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var d = event.angleDelta.x !== 0 ? -event.angleDelta.x : -event.angleDelta.y
                strip.contentX = Math.max(0, Math.min(strip.contentWidth - strip.width, strip.contentX + d * 0.6))
              }
            }
            Row {
              id: stripRow
              spacing: Style.space(8)
              Repeater {
                model: root.presets
                SwatchFrame {
                  required property var modelData
                  required property int index
                  width: strip.parent.tileWidth; height: strip.parent.tileHeight
                  label: modelData.name
                  selected: modelData.id === root.presetId
                  cursor: root.selectedRow === 1 && root.stripCursor === index
                  userMade: !modelData.builtin
                  onClicked: { root.stripCursor = index; root.applyPreset(modelData.id) }
                  onRightClicked: if (!modelData.builtin) root.manageId = (root.manageId === modelData.id ? "" : modelData.id)
                  onHoveredChanged: if (hovered) { root.selectedRow = 1; root.stripCursor = index }
                  SwatchPreview { anchors.fill: parent; look: modelData.values }
                }
              }
            }
          }
          // Fade the strip's right edge so it reads as scrollable.
          Rectangle {
            anchors.right: parent.right
            width: Style.space(18); height: parent.tileHeight
            visible: strip.contentX < strip.contentWidth - strip.width - 2
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "transparent" }
              GradientStop { position: 1; color: root.alphaOf(Commons.Color.background, 0.85) }
            }
          }
        }

        // ---------- Tabs ----------
        Motion.GlassTrack {
          width: parent.width; foreground: root.fg
          Row {
            width: parent.width; spacing: Style.space(2)
            Repeater {
              model: ["Windows", "Texture"]
              Button {
                required property string modelData
                required property int index
                width: (parent.width - Style.space(2)) / 2
                text: modelData; foreground: root.fg; fontFamily: root.family; bordered: false
                active: root.page === index; hasCursor: root.selectedRow === 2 && root.page === index
                onClicked: root.page = index
                onHovered: function(hovered) { if (hovered) root.selectedRow = 2 }
              }
            }
          }
        }

        // ---------- Sliders ----------
        Column {
          width: parent.width
          spacing: Style.space(12)
          Repeater {
            model: root.controls
            GlassSlider {
              required property var modelData
              required property int index
              width: content.width
              spec: modelData
              row: index + 3
            }
          }
        }

        // ---------- Footer: unsaved bar / naming / manage / hint ----------
        Rectangle {
          id: footer
          width: parent.width
          height: Style.space(42)
          radius: Style.space(12)
          readonly property string mode: root.naming ? "name" : root.managed ? "manage" : root.modified ? "dirty" : "idle"
          color: mode === "idle" ? "transparent" : mode === "dirty" ? root.alphaOf(root.accent, 0.12) : root.alphaOf(root.fg, 0.06)
          border.width: mode === "idle" ? 0 : 1
          border.color: mode === "dirty" || mode === "name" ? root.alphaOf(root.accent, 0.35) : root.alphaOf(root.fg, 0.08)

          // idle
          Text {
            visible: footer.mode === "idle"
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(2)
            width: parent.width - Style.space(4)
            elide: Text.ElideRight
            text: root.message || (root.page === 0 ? "Opacity affects whole apps, text included. Right-click your own presets to rename or delete." : "Backdrop controls change what shows through the glass, not the text.")
            color: root.alphaOf(root.fg, 0.6); font.family: root.family; font.pixelSize: Style.font.caption
          }

          // dirty: Unsaved changes · Update · Save as new
          Row {
            visible: footer.mode === "dirty"
            anchors.fill: parent
            anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(6)
            spacing: Style.space(8)
            Rectangle { width: Style.space(6); height: width; radius: width / 2; color: root.accent; anchors.verticalCenter: parent.verticalCenter }
            Text {
              width: parent.width - Style.space(14) - (updateBtn.visible ? updateBtn.width + Style.space(8) : 0) - saveBtn.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.activePreset ? "Unsaved changes" : "Custom look"
              elide: Text.ElideRight
              color: root.fg; font.family: root.family; font.pixelSize: Style.font.body
            }
            Pill { id: updateBtn; visible: !!root.activePreset && !root.activePreset.builtin; text: "Update"; onClicked: root.run(["update-preset", root.presetId]) }
            Pill { id: saveBtn; text: "Save as new"; primary: true; cursor: root.selectedRow === 7; onClicked: root.startNaming() }
          }

          // name: field · Cancel · Save
          Row {
            visible: footer.mode === "name"
            anchors.fill: parent
            anchors.leftMargin: Style.space(4); anchors.rightMargin: Style.space(6)
            spacing: Style.space(6)
            QQC.TextField {
              id: nameField
              width: parent.width - cancelBtn.width - confirmBtn.width - Style.space(12)
              height: Style.space(32)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: root.renaming ? "New name" : "Name this look"
              color: root.fg
              placeholderTextColor: root.alphaOf(root.fg, 0.45)
              selectionColor: root.alphaOf(root.accent, 0.4)
              selectedTextColor: root.fg
              font.family: root.family; font.pixelSize: Style.font.body
              leftPadding: Style.space(10); rightPadding: Style.space(10)
              maximumLength: 40
              background: Rectangle { radius: Style.space(8); color: Qt.rgba(0, 0, 0, 0.22); border.width: 1; border.color: root.alphaOf(root.accent, nameField.activeFocus ? 0.6 : 0.25) }
              onAccepted: root.finishNaming(text)
              Keys.onEscapePressed: root.cancelNaming()
            }
            Pill { id: cancelBtn; text: "Cancel"; onClicked: root.cancelNaming() }
            Pill { id: confirmBtn; text: root.renaming ? "Rename" : "Save"; primary: true; onClicked: root.finishNaming(nameField.text) }
          }

          // manage (right-clicked user preset): name · Rename · Delete
          Row {
            visible: footer.mode === "manage"
            anchors.fill: parent
            anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(6)
            spacing: Style.space(6)
            Text {
              width: parent.width - renameBtn.width - deleteBtn.width - closeBtn.width - Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              text: root.managed ? root.managed.name : ""
              elide: Text.ElideRight
              color: root.fg; font.family: root.family; font.pixelSize: Style.font.body; font.weight: Font.DemiBold
            }
            Pill { id: renameBtn; text: "Rename"; onClicked: root.startRename() }
            Pill { id: deleteBtn; text: "Delete"; danger: true; onClicked: { root.run(["delete-preset", root.manageId]); root.manageId = "" } }
            Pill { id: closeBtn; text: "✕"; onClicked: root.manageId = "" }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  // A preset tile: rounded frame + label, accent ring when applied.
  component SwatchFrame: Item {
    id: tile
    property string label: ""
    property bool selected: false
    property bool cursor: false
    property bool dashed: false
    property bool userMade: false
    readonly property bool hovered: tileMouse.containsMouse
    default property alias content: frame.data
    signal clicked()
    signal rightClicked()

    ClippingRectangle {
      id: frame
      width: parent.width; height: parent.height
      radius: Style.space(10)
      color: tile.dashed ? "transparent" : root.alphaOf(root.fg, 0.06)
    }
    // Dashed outline for the "+ Save" tile (drawn as a faint border).
    Rectangle {
      visible: tile.dashed
      anchors.fill: frame; radius: frame.radius; color: "transparent"
      border.width: 1; border.color: root.alphaOf(root.fg, tile.hovered ? 0.45 : 0.25)
    }
    Rectangle {
      anchors.fill: frame
      anchors.margins: -Style.space(2)
      radius: frame.radius + Style.space(2)
      color: "transparent"
      border.width: tile.selected ? 2 : (tile.cursor || tile.hovered) && !tile.dashed ? 1 : 0
      border.color: tile.selected ? root.accent : root.alphaOf(root.fg, 0.5)
    }
    Text {
      anchors.top: frame.bottom; anchors.topMargin: Style.space(5)
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: (tile.userMade ? "• " : "") + tile.label
      color: tile.selected ? root.fg : root.alphaOf(root.fg, 0.62)
      font.family: root.family; font.pixelSize: Style.font.caption; font.weight: tile.selected ? Font.DemiBold : Font.Normal
    }
    MouseArea {
      id: tileMouse
      anchors.fill: frame
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      enabled: root.loaded
      onClicked: function(mouse) { if (mouse.button === Qt.RightButton) tile.rightClicked(); else tile.clicked() }
    }
  }

  // Mini desktop: the wallpaper with an unfocused and a focused "window". The
  // window shows the wallpaper downsampled by blur strength (cheap blur), the
  // brightness wash, and the theme background at the preset's opacity.
  component SwatchPreview: Item {
    id: prev
    property var look: ({})
    readonly property int blurWidth: Math.max(5, Math.round(150 / Math.max(1, look.size || 6)))

    Image {
      anchors.fill: parent
      source: root.wallpaper + "?" + root.openCount
      sourceSize.width: 160
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
    MiniWindow { preview: prev; x: prev.width * 0.07; y: prev.height * 0.14; width: prev.width * 0.5; height: prev.height * 0.5; opacityValue: prev.look.inactive || 0.7 }
    MiniWindow { preview: prev; x: prev.width * 0.3; y: prev.height * 0.36; width: prev.width * 0.82; height: prev.height * 0.8; opacityValue: prev.look.active || 0.8 }
  }


  component MiniWindow: ClippingRectangle {
    id: win
    property Item preview: null
    property real opacityValue: 0.8
    readonly property var look: preview ? preview.look : ({})
    radius: Style.space(5)
    color: "transparent"
    Image {
      x: -win.x; y: -win.y
      width: win.preview ? win.preview.width : 0; height: win.preview ? win.preview.height : 0
      source: root.wallpaper + "?" + root.openCount
      sourceSize.width: win.preview ? win.preview.blurWidth : 8
      fillMode: Image.PreserveAspectCrop
      smooth: true
      asynchronous: true
    }
    Rectangle {
      anchors.fill: parent
      readonly property real b: win.look.brightness || 1
      color: b >= 1 ? Qt.rgba(1, 1, 1, Math.min(0.5, (b - 1) * 1.6)) : Qt.rgba(0, 0, 0, Math.min(0.6, (1 - b) * 1.4))
    }
    Rectangle { anchors.fill: parent; color: root.alphaOf(Commons.Color.accent, Math.min(0.25, (win.look.vibrancy || 0) * 0.45)) }
    // Exaggerated so the 40–100% range reads at thumbnail size.
    Rectangle { anchors.fill: parent; color: root.alphaOf(Commons.Color.background, 0.15 + Math.max(0, (win.opacityValue - 0.4) / 0.6) * 0.82) }
    Rectangle { anchors.fill: parent; radius: win.radius; color: "transparent"; border.width: 1; border.color: root.alphaOf(root.fg, 0.18) }
  }

  // Slim slider row: label · value (and "· was X" when it differs from the
  // applied preset) · 6px track with a tick at the preset's value.
  component GlassSlider: Column {
    id: sl
    property var spec: ({})
    property int row: 0
    property bool dragging: false
    property real live: Number(root.values[spec.key] || 0)
    readonly property real base: root.activePreset ? Number(root.activePreset.values[spec.key]) : NaN
    readonly property bool changed: !isNaN(base) && Math.abs(live - base) > 0.0015
    readonly property real range: Math.max(0.0001, spec.max - spec.min)
    readonly property real progress: Math.max(0, Math.min(1, (live - spec.min) / range))
    spacing: Style.space(7)
    enabled: root.loaded
    Connections { target: root; function onValuesChanged() { if (!sl.dragging) sl.live = Number(root.values[sl.spec.key] || 0) } }

    Item {
      width: parent.width
      height: Math.max(nameText.implicitHeight, valueText.implicitHeight)
      Text {
        id: nameText
        text: sl.spec.label
        color: root.fg; font.family: root.family; font.pixelSize: Style.font.body
        font.weight: root.selectedRow === sl.row ? Font.DemiBold : Font.Normal
      }
      Text {
        id: valueText
        anchors.right: parent.right
        text: root.fmt(sl.spec.key, sl.live) + (sl.changed ? "  · was " + root.fmt(sl.spec.key, sl.base) : "")
        color: sl.changed ? root.accent : root.alphaOf(root.fg, 0.6)
        font.family: root.family; font.pixelSize: Style.font.body; font.weight: sl.changed ? Font.DemiBold : Font.Normal
      }
    }
    Item {
      width: parent.width
      height: Style.space(12)
      Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Style.space(6); radius: height / 2
        color: root.alphaOf(root.fg, mouse.containsMouse || sl.dragging ? 0.16 : 0.1)
        Rectangle {
          width: Math.max(track.height, track.width * sl.progress); height: parent.height; radius: parent.radius
          color: sl.changed ? root.accent : root.alphaOf(root.fg, 0.78)
          Behavior on width { enabled: !sl.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }
      Rectangle {
        visible: sl.changed
        x: track.width * Math.max(0, Math.min(1, (sl.base - sl.spec.min) / sl.range)) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 2; height: Style.space(12); radius: 1
        color: root.alphaOf(root.fg, 0.55)
      }
      MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: -Style.space(4); anchors.bottomMargin: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function valueAt(x) {
          var f = Math.max(0, Math.min(1, x / track.width))
          var v = sl.spec.min + f * sl.range
          v = Math.round(v / sl.spec.step) * sl.spec.step
          return Math.round(Math.max(sl.spec.min, Math.min(sl.spec.max, v)) * 1000) / 1000
        }
        onEntered: root.selectedRow = sl.row
        onPressed: function(m) { sl.dragging = true; root.selectedRow = sl.row; sl.live = valueAt(m.x) }
        onPositionChanged: function(m) { if (sl.dragging) sl.live = valueAt(m.x) }
        onReleased: { sl.dragging = false; root.save(sl.spec.key, sl.live) }
        onWheel: function(w) {
          var v = Math.round(Math.max(sl.spec.min, Math.min(sl.spec.max, sl.live + (w.angleDelta.y > 0 ? 1 : -1) * sl.spec.step)) * 1000) / 1000
          sl.live = v; root.save(sl.spec.key, v)
        }
      }
    }
  }

  // Small pill button used in the footer.
  component Pill: Rectangle {
    id: pill
    property string text: ""
    property bool primary: false
    property bool danger: false
    property bool cursor: false
    signal clicked()
    height: Style.space(28)
    width: pillText.implicitWidth + Style.space(22)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    radius: Style.space(8)
    color: primary ? root.accent : danger && pillMouse.containsMouse ? root.alphaOf(Commons.Color.urgent, 0.25) : pillMouse.containsMouse ? root.alphaOf(root.fg, 0.1) : "transparent"
    border.width: cursor ? 2 : 0
    border.color: root.alphaOf(root.fg, 0.7)
    opacity: root.busy ? 0.6 : 1
    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.text
      color: pill.primary ? Commons.Color.background : pill.danger ? Commons.Color.urgent : root.alphaOf(root.fg, 0.8)
      font.family: root.family; font.pixelSize: Style.font.caption + 1; font.weight: pill.primary ? Font.Bold : Font.DemiBold
    }
    MouseArea { id: pillMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !root.busy; onClicked: pill.clicked() }
  }
}
