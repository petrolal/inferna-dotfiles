import "../denon.bar/panels" as Motion
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  // Glass surfaces: calm sentence-case taglines instead of tracked capitals.
  function glassSentence(v) { var t = String(v || ""); return t.length ? t.charAt(0).toUpperCase() + t.slice(1).toLowerCase() : t }

  moduleName: "inferna.monitor"
  ipcTarget: "inferna.monitor"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0
  property bool nightLightOn: false
  property int nightLightTemp: 0
  property bool displaysOpen: false

  function toggleNightLight() {
    root.nightLightOn = !root.nightLightOn   // optimistic; status re-read after
    if (!nightToggleProc.running) nightToggleProc.running = true
  }
  function focusedSummary() {
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      if (d && d.focused) return (/^eDP/.test(d.name) ? "Built-in" : d.name) + " · " + d.width + " × " + d.height
    }
    return ""
  }
  function looksLike() {
    var s = Number(root.monitorScale) || 1
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      if (d && d.focused) return "Looks like " + Math.round(d.width / s) + " × " + Math.round(d.height / s)
    }
    return ""
  }

  // Cursor model shared by keyboard and mouse. Sections:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel
  //                  (mirrors Audio's slider rows). Only present if a
  //                  controllable backlight was detected.
  //   "scale"      - 6 Button scale presets; treated as a single
  //                  horizontal row from j/k's perspective. h/l moves
  //                  between presets, identical to bluetooth's header.
  //   "monitors"   - vertical display row list for enabling/disabling displays;
  //                  j/k walks each row.
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property var scaleValues: {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.availableScales(scalePresets, display.width, display.height)
    }
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (inferna-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    if (brightnessAvailable) list.push("brightness")
    list.push("toggles")
    if (displaysOpen && displays.length > 1) list.push("monitors")
    list.push("textsize")
    list.push("scale")
    return list
  }

  function sectionCount(section) {
    if (section === "brightness") return 0  // only the slider sentinel at -1
    if (section === "textsize") return 0    // slider sentinel at -1, like brightness
    if (section === "scale") return scaleValues.length
    if (section === "toggles") return 2
    if (section === "monitors") return displays.length
    return 0
  }

  function sectionIsSingleRow(section) {
    // brightness and text size are lone sliders; scale presets sit horizontally.
    return section === "brightness" || section === "textsize" || section === "scale" || section === "toggles"
  }

  function sectionFirstIndex(section) {
    if (section === "brightness" || section === "textsize") return -1
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l: in scale section, walks the preset row; everywhere else, no-op
  // because adjustBrightness handles horizontal motion on the brightness
  // slider.
  function moveCursorH(delta) {
    if (focusSection !== "scale" && focusSection !== "toggles") return
    var next = selectedIndex + delta
    var max = focusSection === "toggles" ? 1 : scaleValues.length - 1
    if (next < 0) next = 0
    if (next > max) next = max
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "toggles") {
      if (selectedIndex === 0) toggleNightLight()
      else displaysOpen = !displaysOpen
      return
    }
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < displays.length) {
      var d = displays[selectedIndex]
      if (d) toggleDisplay(d.name, d.enabled)
    }
    // brightness: no separate action; the slider value is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      // brightness/text size use the -1 sentinel; scale clamps into the presets.
      if (focusSection === "brightness" || focusSection === "textsize") selectedIndex = -1
      else if (focusSection === "toggles") { if (selectedIndex < 0 || selectedIndex > 1) selectedIndex = 0 }
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      scale: root.monitorScale,
      displays: root.displays
    })
  }

  IpcHandler {
    target: "inferna.monitor"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!nightStatusProc.running) nightStatusProc.running = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["inferna-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("inferna.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.matchingScaleIndex(scaleValues, monitorScale, display.width, display.height)
    }
    return -1
  }

  function effectiveScale(scale) {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.cleanScale(scale, display.width, display.height)
    }
    return normalizeScale(scale)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return

    // hyprctl keyword is rejected under the Lua config ("non-legacy parsers"),
    // so drive the monitor through the hl.monitor eval API instead.
    var output = '"' + name.replace(/[\\"]/g, "\\$&") + '"'
    var expr = enabled
      ? 'hl.monitor({ output = ' + output + ', disabled = true })'
      : 'hl.monitor({ output = ' + output + ', disabled = false, mode = "preferred", position = "auto", scale = "auto" })'
    actionProc.command = ["hyprctl", "eval", expr]
    if (!actionProc.running) actionProc.running = true
  }

  function setScale(scale) {
    actionProc.command = ["bash", "-c", "inferna-hyprland-monitor-scaling " + scale]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["inferna-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      refresh()
      displaysOpen = false
      if (brightnessAvailable) {
        focusSection = "brightness"
        selectedIndex = -1
      } else {
        focusSection = "scale"
        selectedIndex = 0
      }
      cursorActive = false
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["inferna-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `inferna-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0 —
    // visible as a "bounce to zero" after h/l keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  Process {
    id: nightStatusProc
    command: ["inferna-toggle-nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var st = JSON.parse(text)
          root.nightLightOn = !!st.enabled
          root.nightLightTemp = st.temperature || 0
        } catch (e) {}
      }
    }
  }

  Process {
    id: nightToggleProc
    command: ["inferna-toggle-nightlight"]
    onRunningChanged: if (!running) nightStatusProc.running = true
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { if (!Motion.PanelMotion.commitHover(root)) root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  Motion.PopupPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else if (root.focusSection === "scale" || root.focusSection === "toggles") root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Header: Display · which screen ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(titleText.implicitHeight, subText.implicitHeight)
            Text {
              id: titleText
              text: "Display"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title + 1
              font.weight: Font.Bold
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              id: subText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.focusedSummary()
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption + 1
            }
          }

          // ---------- Brightness: big slider (D-A) ----------
          Item {
            id: brightnessRow
            visible: root.brightnessAvailable
            width: parent.width
            height: Style.space(48)
            readonly property bool hasCursor: root.cursorActive && root.focusSection === "brightness"

            BigSlider {
              id: brightnessSlider
              anchors.fill: parent
              bar: root.bar
              glyph: "󰃠"
              minimum: 1
              maximum: 100
              step: 0.05
              value: root.brightnessPercent
              onMoved: function(v) { root.previewBrightness(Math.round(v)) }
              onReleased: function(v) { brightnessDebounce.stop(); root.setBrightness(Math.round(v)) }
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
              // Sits on the fill near 100%, on the track otherwise.
              color: brightnessSlider.progress > 0.9 ? Commons.Color.background : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.65)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
            }
            Rectangle {
              anchors.fill: parent
              anchors.margins: -Style.space(2)
              radius: Style.space(10)
              color: "transparent"
              border.width: brightnessRow.hasCursor ? 2 : 0
              border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6)
            }
            HoverHandler {
              onHoveredChanged: if (hovered && !root.reflowingText) {
                root.cursorActive = true
                root.focusSection = "brightness"
                root.selectedIndex = -1
              }
            }
          }

          // ---------- Quick tiles: Night light · Displays ----------
          Row {
            width: parent.width
            spacing: Style.space(8)
            QuickTile {
              width: (parent.width - parent.spacing) / 2
              tileIndex: 0
              glyph: "󰖔"
              title: "Night light"
              subtitle: root.nightLightOn ? "On · " + (root.nightLightTemp || 4000) + "K" : "Off"
              on: root.nightLightOn
              onActivated: root.toggleNightLight()
            }
            QuickTile {
              width: (parent.width - parent.spacing) / 2
              tileIndex: 1
              glyph: root.displays.length > 1 ? "󰍺" : "󰍹"
              title: "Displays"
              subtitle: root.displays.length + " connected" + (root.mirrorEnabled ? " · mirrored" : "")
              on: false
              open: root.displaysOpen
              onActivated: root.displaysOpen = !root.displaysOpen
            }
          }

          // ---------- Displays (expanded from the tile) ----------
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.displaysOpen

            Repeater {
              model: root.displays
              MonitorRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                display: modelData
                rowIndex: index
              }
            }
            Text {
              visible: root.displays.length <= 1
              width: parent.width
              leftPadding: Style.space(8)
              text: "Plug in a monitor to extend or mirror."
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.55)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption + 1
            }
          }

          // ---------- Text size: Aa ——— Aa ----------
          Rectangle {
            id: textSizeRow
            width: parent.width
            height: textCol.implicitHeight + Style.space(22)
            radius: Style.space(14)
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05)
            border.width: root.cursorActive && root.focusSection === "textsize" ? 2 : 0
            border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6)

            Column {
              id: textCol
              x: Style.space(12)
              y: Style.space(11)
              width: parent.width - Style.space(24)
              spacing: Style.space(6)
              Item {
                width: parent.width
                implicitHeight: textSizeLabel.implicitHeight
                Text {
                  id: textSizeLabel
                  text: "Text size"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.right: parent.right
                  text: (textSizeSlider.dragging ? root.textSizeStops[Math.round(textSizeSlider.liveValue)] : root.displayedTextPx()) + " px"
                  color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(10)
                Text {
                  id: smallAa
                  text: "Aa"
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
                PanelSlider {
                  id: textSizeSlider
                  bar: root.bar
                  width: parent.width - smallAa.width - bigAa.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  minimum: 0
                  maximum: root.textSizeStops.length - 1
                  step: 1
                  integer: true
                  tickCount: root.textSizeStops.length
                  tickColor: Qt.rgba(0, 0, 0, 0.35)
                  value: root.currentTextIndex()
                  onReleased: function(v) { root.markReflowing(); root.textSizePreviewIndex = Math.round(v); root.setTextSize(root.textSizeStops[Math.round(v)]) }
                }
                Text {
                  id: bigAa
                  text: "Aa"
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title + 3
                }
              }
            }
            HoverHandler {
              onHoveredChanged: if (hovered && !root.reflowingText) {
                root.cursorActive = true
                root.focusSection = "textsize"
                root.selectedIndex = -1
              }
            }
          }

          // ---------- Scale: segmented ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: scaleLabel.implicitHeight
              Text {
                id: scaleLabel
                x: Style.space(2)
                text: "Scale" + (root.enabledDisplayCount > 1 && root.focusedMonitor ? " · " + root.focusedMonitor : "")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(2)
                text: root.looksLike()
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption + 1
              }
            }

            Motion.GlassTrack {
              width: parent.width
              foreground: root.bar.foreground
              Row {
                id: scaleRow
                width: parent.width
                spacing: Style.space(2)
                readonly property real cellWidth: root.scaleValues.length > 0
                  ? (width - spacing * (root.scaleValues.length - 1)) / root.scaleValues.length
                  : 0
                Repeater {
                  model: root.scaleValues
                  ScalePill {
                    required property string modelData
                    required property int index
                    scaleValue: modelData
                    scaleIndex: index
                    width: scaleRow.cellWidth
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  // D-A quick tile: glyph, title, status; solid accent when on.
  component QuickTile: Rectangle {
    id: qt
    property int tileIndex: 0
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool on: false
    property bool open: false
    signal activated()
    readonly property bool hasCursor: root.cursorActive && root.focusSection === "toggles" && root.selectedIndex === tileIndex
    readonly property color ink: on ? Commons.Color.background : root.bar.foreground
    height: Style.space(70)
    radius: Style.space(14)
    color: on ? Commons.Color.accent
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, tileMouse.containsMouse || open ? 0.12 : 0.08)
    border.width: hasCursor ? 2 : 0
    border.color: on ? Commons.Color.background : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6)
    Behavior on color { ColorAnimation { duration: 160 } }

    Text {
      x: Style.space(12); y: Style.space(11)
      text: qt.glyph
      color: qt.ink
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title + 2
    }
    Text {
      visible: qt.open
      anchors.right: parent.right; anchors.rightMargin: Style.space(12)
      y: Style.space(11)
      text: "󰅀"
      color: Qt.rgba(qt.ink.r, qt.ink.g, qt.ink.b, 0.6)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
    Column {
      x: Style.space(12)
      anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(10)
      width: parent.width - Style.space(24)
      spacing: Style.space(1)
      Text {
        width: parent.width; elide: Text.ElideRight
        text: qt.title
        color: qt.ink
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.weight: qt.on ? Font.Bold : Font.DemiBold
      }
      Text {
        width: parent.width; elide: Text.ElideRight
        text: qt.subtitle
        color: Qt.rgba(qt.ink.r, qt.ink.g, qt.ink.b, 0.7)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption + 1
      }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: qt.activated()
      onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
        root.cursorActive = true
        root.focusSection = "toggles"
        root.selectedIndex = qt.tileIndex
      }
    }
  }

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    text: root.effectiveScale(scaleValue) + "×"
    fontSize: Style.font.bodySmall
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY + Style.space(1)
    bordered: false

    active: root.activeScaleIndex() === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }

  component MonitorRow: CursorSurface {
    id: monitorRow
    required property var display
    required property int rowIndex

    readonly property bool isFocused: display && display.focused
    readonly property bool canToggle: display && (!display.enabled || root.enabledDisplayCount > 1)

    hasCursor: root.cursorActive && root.focusSection === "monitors" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(monitorRow)
    current: isFocused
    foreground: root.bar.foreground
    fill: Style.hoverFillFor(root.bar.foreground, Commons.Color.accent)
    currentFill: Style.selectedFillFor(root.bar.foreground, Commons.Color.accent)
    implicitHeight: monitorInner.implicitHeight + Style.spacing.xl
    opacity: canToggle ? 1.0 : 0.45

    Row {
      id: monitorInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "󰍹"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.name + (monitorRow.display.focused ? " · focused" : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(14) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.enabled ? "󰄬" : ""
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        width: Style.space(14)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: monitorRow.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
        root.cursorActive = true
        root.focusSection = "monitors"
        root.selectedIndex = monitorRow.rowIndex
      }
      onClicked: if (monitorRow.canToggle) root.toggleDisplay(monitorRow.display.name, monitorRow.display.enabled)
    }
  }
}
