import "../denon.bar/panels" as Motion
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "denon.touchpad"
  ipcTarget: "denon.touchpad"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color panelForeground: bar ? bar.foreground : Color.foreground
  readonly property string panelFont: bar ? bar.fontFamily : Style.font.family
  readonly property string helper: Quickshell.env("HOME") + "/.local/share/touchpad-control/control.py"
  property var values: ({pointer: 0, scroll: 0.4, t3_scroll: 0.28, tap_to_click: true, tap_and_drag: true, disable_while_typing: false, drag_lock: 0})
  property bool available: false
  property bool loaded: false
  property var pending: ({})
  property string message: "Loading touchpad settings…"
  property int selectedRow: 0
  property string actionOutput: ""
  readonly property var keys: ["pointer", "scroll", "t3_scroll", "tap_to_click", "disable_while_typing", "tap_and_drag"]

  function refresh() {
    if (!readProc.running && !writeProc.running && Object.keys(pending).length === 0) readProc.running = true
  }
  function receive(text, fromWrite) {
    try {
      const state = JSON.parse(text)
      available = !!state.available
      loaded = true
      if (state.values) values = Object.assign({}, state.values, pending)
      message = state.ok === false || (state.errors && state.errors.length)
        ? state.errors.join("\n") : (fromWrite ? "Saved · takes effect immediately" : "Changes are saved automatically")
    } catch (error) { message = "Could not read touchpad settings." }
  }
  function preview(key, value) {
    const next = Object.assign({}, values)
    next[key] = value
    values = next
  }
  function save(key, value) {
    if (!available || !loaded) return
    preview(key, value)
    const next = Object.assign({}, pending)
    next[key] = value
    pending = next
    message = "Saving…"
    drain()
  }
  function drain() {
    if (writeProc.running || readProc.running) return
    const names = Object.keys(pending)
    if (!names.length) return
    const key = names[0]
    const value = pending[key]
    const next = Object.assign({}, pending)
    delete next[key]
    pending = next
    actionOutput = ""
    writeProc.command = ["python3", helper, "set", key, String(value)]
    writeProc.running = true
  }
  function adjust(dx) {
    if (selectedRow < 3) {
      const key = keys[selectedRow]
      const min = selectedRow === 0 ? -1 : 0.1
      const max = selectedRow === 0 ? 1 : 1.5
      const step = selectedRow === 0 ? 0.05 : 0.02
      save(key, Math.round(Math.max(min, Math.min(max, values[key] + dx * step)) * 100) / 100)
    }
  }
  function activate() {
    if (selectedRow >= 3 && selectedRow < 6) save(keys[selectedRow], !values[keys[selectedRow]])
    if (selectedRow === 6) resetSpeeds()
  }
  function resetSpeeds() {
    save("pointer", 0)
    save("scroll", 0.4)
    save("t3_scroll", 0.4)
  }
  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  IpcHandler {
    target: "denon.touchpad"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function state(): string { return JSON.stringify({loaded: root.loaded, available: root.available, values: root.values, message: root.message, busy: writeProc.running}) }
    function set(key: string, value: string): void {
      if (root.keys.indexOf(key) < 0) return
      root.save(key, root.keys.indexOf(key) < 3 ? Number(value) : value === "true")
    }
  }
  Process {
    id: readProc
    command: ["python3", root.helper, "state"]
    stdout: StdioCollector { onStreamFinished: root.receive(text, false) }
    onExited: Qt.callLater(root.drain)
  }
  Process {
    id: writeProc
    stdout: StdioCollector { onStreamFinished: { root.actionOutput = text; root.receive(text, true) } }
    onExited: function(code, status) {
      if (code !== 0 && !root.actionOutput) root.message = "Could not save settings. Reopen this panel to retry."
      Qt.callLater(root.drain)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰟸"
    tooltipText: "Touchpad · pointer, scrolling & taps"
    onPressed: if (!Motion.PanelMotion.commitHover(root)) root.toggle()
  }
  Motion.PopupPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyboard
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyboard
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy) root.selectedRow = Math.max(0, Math.min(6, root.selectedRow + dy))
        else root.adjust(dx)
      }
      onActivateRequested: root.activate()
      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)
        Text {
          text: "Touchpad"
          color: root.panelForeground
          font.family: root.panelFont
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          width: parent.width
          text: root.available ? "ASUS built-in touchpad" : "Touchpad unavailable"
          color: root.panelForeground
          opacity: 0.7
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }
        SpeedControl { label: "Pointer speed"; keyName: "pointer"; rowIndex: 0; minimum: -1; maximum: 1 }
        SpeedControl { label: "Scroll speed"; keyName: "scroll"; rowIndex: 1; minimum: 0.1; maximum: 1.5 }
        SpeedControl { label: "T3 Code scroll speed"; keyName: "t3_scroll"; rowIndex: 2; minimum: 0.1; maximum: 1.5 }
        Motion.GlassSeparator { foreground: root.panelForeground }
        TapControl { label: "Tap to click"; keyName: "tap_to_click"; rowIndex: 3 }
        TapControl { label: "Allow touchpad while typing"; keyName: "disable_while_typing"; rowIndex: 4; inverted: true }
        TapControl { label: "Double-tap and hold to drag"; keyName: "tap_and_drag"; rowIndex: 5 }
        Text {
          width: parent.width
          text: "Allowing taps while typing may help missed taps after keystrokes, but also permits accidental touches. This touchpad has no adjustable tap-pressure threshold."
          wrapMode: Text.WordWrap
          color: root.panelForeground
          opacity: 0.7
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }
        Button {
          text: "Reset speeds"
          foreground: root.panelForeground
          fontFamily: root.panelFont
          bordered: true
          hasCursor: root.selectedRow === 6
          enabled: root.available && root.loaded
          onClicked: root.resetSpeeds()
          onHovered: function(hovered) { if (hovered) root.selectedRow = 6 }
        }
        Text {
          width: parent.width
          text: root.message
          wrapMode: Text.WordWrap
          color: root.panelForeground
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          opacity: 0.75
        }
      }
    }
  }

  component SpeedControl: Column {
    required property string label
    required property string keyName
    required property int rowIndex
    required property real minimum
    required property real maximum
    width: parent.width
    spacing: Style.space(4)
    enabled: root.available && root.loaded
    opacity: enabled ? 1 : 0.5
    Row {
      width: parent.width
      Text {
        width: parent.width * 0.75
        text: label
        color: root.panelForeground
        font.family: root.panelFont
        font.pixelSize: Style.font.body
        font.bold: root.selectedRow === rowIndex
      }
      Text {
        width: parent.width * 0.25
        horizontalAlignment: Text.AlignRight
        text: keyName === "pointer" ? Math.round(root.values[keyName] * 100) : Math.round(root.values[keyName] / 0.4 * 100) + "%"
        color: root.panelForeground
        font.family: root.panelFont
        font.pixelSize: Style.font.body
      }
    }
    PanelSlider {
      width: parent.width
      bar: root.bar
      value: root.values[keyName]
      minimum: parent.minimum
      maximum: parent.maximum
      step: keyName === "pointer" ? 0.05 : 0.02
      onMoved: function(value) { root.selectedRow = rowIndex; root.preview(keyName, Math.round(value * 100) / 100) }
      onReleased: function(value) { root.save(keyName, Math.round(value * 100) / 100) }
    }
  }
  component TapControl: Button {
    required property string label
    required property string keyName
    required property int rowIndex
    property bool inverted: false
    readonly property bool checked: inverted ? !root.values[keyName] : !!root.values[keyName]
    width: parent.width
    text: (checked ? "󰄬  " : "○  ") + label
    leftAlign: true
    bordered: true
    active: checked
    hasCursor: root.selectedRow === rowIndex
    foreground: root.panelForeground
    fontFamily: root.panelFont
    fontSize: Style.font.body
    enabled: root.available && root.loaded
    onClicked: root.save(keyName, !root.values[keyName])
    onHovered: function(hovered) { if (hovered) root.selectedRow = rowIndex }
  }
}
