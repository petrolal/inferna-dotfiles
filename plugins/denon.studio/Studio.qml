import "../denon.bar/panels" as Motion
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Studio (Pebble Shell, Paper "C · Side nav"). One drawer for the look of the
// desktop with every setting of each tool: Glass, Depth, Tricky Tiles and
// Display down the left, the chosen tool's full controls on the right, in the
// sleek "Tide" card language. Every change goes straight to that tool's own
// helper (the same CLI its own panel uses), so the tools stay the source of
// truth; their own panels still open over IPC and stay tucked off the rail.
Panel {
  id: root
  moduleName: "denon.studio"
  ipcTarget: "denon.studio"
  implicitWidth: icon.implicitWidth
  implicitHeight: icon.implicitHeight

  // ---------------------------------------------------------------- look
  readonly property color fg: Commons.Color.popups.text
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.4)
  readonly property color hair: Qt.rgba(fg.r, fg.g, fg.b, 0.16)
  readonly property color wash: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
  readonly property color accent: Commons.Color.accent
  readonly property color warm: Qt.tint(Commons.Color.accent, Qt.rgba(1, 0.75, 0.3, 0.55))
  readonly property color ink: Commons.Color.popups.background
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- helpers
  readonly property string home: Quickshell.env("HOME")
  readonly property string glassHelper: home + "/.local/share/omarchy-glass/control.py"
  readonly property string depthHelper: home + "/.local/share/omarchy-recess/control.py"
  readonly property string tilesHelper: home + "/.config/inferna/plugins/io.github.denonmaryland.tricky-tiles/helpers/control.py"

  // ---------------------------------------------------------------- state
  property string page: "glass"
  readonly property var pages: [
    { id: "glass", label: "Glass", glyph: "󰂵" },
    { id: "depth", label: "Depth", glyph: "󰆧" },
    { id: "tiles", label: "Tricky Tiles", glyph: "󰕮" },
    { id: "display", label: "Display", glyph: "󰍹" }
  ]

  property var glass: ({})
  property var glassPresets: []
  property string glassPreset: ""
  property var depth: ({})
  property string depthTheme: "dark"
  property string depthProfile: ""
  readonly property string profile: depthProfile !== "" ? depthProfile : depthTheme
  property var tiles: ({})
  property var tilesPresets: ({})
  property real brightness: 0.5
  property bool nightOn: false
  property string display: ""

  readonly property bool depthRaised: depth.style === "raised"
  readonly property var depthProf: depth.styles && depth.styles[depthRaised ? "raised" : "recessed"]
    ? (depth.styles[depthRaised ? "raised" : "recessed"][profile] || {}) : {}
  readonly property var depthLooks: depthRaised
    ? [{ id: "soft", label: "Soft" }, { id: "pebble", label: "Pebble" }, { id: "lifted", label: "Lifted" }]
    : [{ id: "subtle", label: "Subtle" }, { id: "carved", label: "Carved" }, { id: "deep", label: "Deep" }]
  readonly property var tilesOrder: ["spring", "glide", "snappy", "lively", "reduced"]

  onOpenedChanged: if (opened) refresh()

  // `omarchy-shell denon.studio.page show depth` opens Studio on a page.
  IpcHandler {
    target: "denon.studio.page"
    function show(name: string): void { root.page = name; root.open() }
  }

  function refresh() {
    if (!glassRead.running) glassRead.running = true
    if (!depthRead.running) depthRead.running = true
    if (!tilesRead.running) tilesRead.running = true
    if (!displayRead.running) displayRead.running = true
  }
  function parse(text) { try { return JSON.parse(text) } catch (e) { return {} } }

  // Writes run one after another; the state is re-read once they land.
  property var queue: []
  function write(cmd) {
    queue = queue.concat([cmd])
    if (!writer.running) next()
  }
  function next() {
    if (queue.length === 0) { refresh(); return }
    writer.command = queue[0]
    queue = queue.slice(1)
    writer.running = true
  }
  Process { id: writer; onExited: root.next() }

  function glassSet(key, value) {
    var g = Object.assign({}, glass); g[key] = value; glass = g
    write(["python3", glassHelper, "set", key, String(value)])
  }
  function glassUsePreset(id) { glassPreset = id; write(["python3", glassHelper, "preset", id]) }
  function depthSet(key, value, perProfile) {
    var cmd = ["python3", depthHelper, "set", key, String(value)]
    write(perProfile ? cmd.concat(["--profile", profile]) : cmd)
  }
  function depthLook(id) { write(["python3", depthHelper, "preset", id, "--profile", profile]) }
  function depthMode(mode) {
    var wasOff = depth.enabled === false
    if (mode === "flat") { depth = Object.assign({}, depth, { enabled: false }); depthSet("enabled", "false"); return }
    depth = Object.assign({}, depth, { enabled: true, style: mode })
    depthSet("style", mode)
    if (wasOff) depthSet("enabled", "true")
  }
  function tilesSet(key, value) {
    var t = Object.assign({}, tiles); t[key] = value; tiles = t
    write(["python3", tilesHelper, "set", key, String(value)])
  }
  function tilesUsePreset(id) { write(["python3", tilesHelper, "preset", id]) }
  function setBrightness(f) {
    brightness = Math.max(0.01, Math.min(1, f))
    var mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var cmd = ["omarchy-brightness-display", "--no-osd"]
    if (mon) cmd = cmd.concat(["--monitor", mon])
    Quickshell.execDetached(cmd.concat([Math.round(brightness * 100) + "%"]))
  }
  function openFull(target) { root.close(); Quickshell.execDetached(["omarchy-shell", target, "open"]) }

  Process {
    id: glassRead
    command: ["python3", root.glassHelper, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var d = root.parse(text)
        if (d.values) root.glass = d.values
        if (d.presets) root.glassPresets = d.presets
        root.glassPreset = d.preset || (d.values ? d.values.preset || "" : "")
      }
    }
  }
  Process {
    id: depthRead
    command: ["python3", root.depthHelper, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var d = root.parse(text)
        if (d.values) root.depth = d.values
        if (d.theme) root.depthTheme = d.theme
      }
    }
  }
  Process {
    id: tilesRead
    command: ["python3", root.tilesHelper, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var d = root.parse(text)
        if (d.values) root.tiles = d.values
        if (d.presets) root.tilesPresets = d.presets
      }
    }
  }
  Process {
    id: displayRead
    command: ["sh", "-c", "echo bright=$(brightnessctl -m 2>/dev/null | head -1 | cut -d, -f4 | tr -d '%'); echo night=$(omarchy toggle nightlight --status 2>/dev/null | grep -o '\"enabled\":[a-z]*' | cut -d: -f2); echo ---; hyprctl -j monitors"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(text).split("---\n"), lines = (parts[0] || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var kv = lines[i].split("="), v = (kv[1] || "").trim()
          if (kv[0] === "bright" && v !== "") root.brightness = Number(v) / 100
          else if (kv[0] === "night") root.nightOn = v === "true"
        }
        try {
          var mons = JSON.parse(parts[1] || "[]")
          var m = mons.filter(function(x) { return x.focused })[0] || mons[0]
          if (m) root.display = m.name + " · " + m.width + "×" + m.height + " · " + (Math.round(m.scale * 100) / 100) + "× · " + Math.round(m.refreshRate) + " Hz"
        } catch (e) {}
      }
    }
  }

  BarIconButton {
    id: icon
    anchors.fill: parent
    bar: root.bar
    text: "󰫢"
    tooltipText: "Studio · Glass, Depth, Tricky Tiles, Display"
    onPressed: if (!Motion.PanelMotion.commitHover(root)) root.toggle()
  }

  // ================================================================ parts
  component Label: Text {
    color: root.fg
    font.family: root.family
    font.pixelSize: Style.space(13)
    font.weight: Font.Medium
    renderType: Text.NativeRendering
  }
  component Caption: Text {
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.space(12)
    renderType: Text.NativeRendering
  }
  component Section: Text {
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.space(12)
    font.weight: Font.Medium
    topPadding: Style.space(4)
    renderType: Text.NativeRendering
  }

  component Switch: Rectangle {
    id: sw
    property bool on: false
    signal toggled(bool next)
    width: Style.space(36); height: Style.space(22); radius: height / 2
    color: on ? root.accent : root.hair
    Behavior on color { ColorAnimation { duration: 160 } }
    Rectangle {
      width: parent.height - Style.space(6); height: width; radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      x: sw.on ? parent.width - width - Style.space(3) : Style.space(3)
      color: sw.on ? root.ink : root.fg
      Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled(!sw.on) }
  }

  // Title + sub line + on/off for the top of each page.
  component PageHead: Item {
    id: head
    property string title: ""
    property string sub: ""
    property bool hasSwitch: true
    property bool on: true
    signal toggled(bool next)
    width: parent ? parent.width : 0
    implicitHeight: Math.max(headCol.implicitHeight, Style.space(24))
    Column {
      id: headCol
      anchors.left: parent.left
      anchors.right: headSwitch.left
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(2)
      Text { text: head.title; color: root.fg; font.family: root.family; font.pixelSize: Style.space(16); font.weight: Font.Medium; renderType: Text.NativeRendering }
      Caption { width: parent.width; text: head.sub; elide: Text.ElideRight; visible: text !== "" }
    }
    Switch { id: headSwitch; visible: head.hasSwitch; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: head.on; onToggled: function(next) { head.toggled(next) } }
  }

  // A labelled hairline slider: label left, value right, track below.
  component Fader: Item {
    id: f
    property string label: ""
    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0.01
    property real factor: 100
    property int decimals: 0
    property string unit: "%"
    property color tint: root.accent
    property bool enabledLook: true
    property real draft: NaN
    signal committed(real v)
    readonly property real shown: isNaN(draft) ? value : draft
    readonly property real frac: Math.max(0, Math.min(1, (shown - from) / Math.max(0.0001, to - from)))
    function snap(v) { return Math.max(from, Math.min(to, Math.round(v / step) * step)) }
    width: parent ? parent.width : 0
    implicitHeight: Style.space(38)
    opacity: enabledLook ? 1 : 0.45
    Label { text: f.label; anchors.left: parent.left; anchors.top: parent.top }
    Text {
      anchors.right: parent.right; anchors.top: parent.top
      text: (f.shown * f.factor).toFixed(f.decimals) + "<span style='color:" + root.muted + "; font-size:" + Style.space(11) + "px'>" + f.unit + "</span>"
      textFormat: Text.StyledText
      color: root.fg; font.family: root.family; font.pixelSize: Style.space(14)
      renderType: Text.NativeRendering
    }
    Item {
      id: trk
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      height: Style.space(14)
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; radius: 1; color: root.hair }
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * f.frac; height: 4; radius: 2; color: f.tint }
      Rectangle {
        x: Math.max(0, Math.min(parent.width - width, parent.width * f.frac - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(13); height: width; radius: width / 2
        color: root.fg
        scale: fMouse.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
      }
      MouseArea {
        id: fMouse
        anchors.fill: parent
        anchors.topMargin: -Style.space(8)
        anchors.bottomMargin: -Style.space(4)
        enabled: f.enabledLook
        cursorShape: Qt.PointingHandCursor
        function at(x) { return f.from + (f.to - f.from) * Math.max(0, Math.min(1, x / trk.width)) }
        onPressed: function(mouse) { f.draft = f.snap(at(mouse.x)) }
        onPositionChanged: function(mouse) { if (pressed) f.draft = f.snap(at(mouse.x)) }
        onReleased: { var v = f.draft; f.draft = NaN; if (!isNaN(v)) f.committed(v) }
        onWheel: function(wheel) { f.committed(f.snap(f.value + (wheel.angleDelta.y > 0 ? f.step : -f.step))) }
      }
    }
  }

  // Words to pick from, the chosen one in the accent with a dot under it.
  component Choice: Item {
    id: ch
    property string label: ""
    property var options: []        // [{id, label}]
    property string current: ""
    signal picked(string id)
    width: parent ? parent.width : 0
    implicitHeight: Style.space(28)
    Label { text: ch.label; anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: Style.space(3) }
    Row {
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(14)
      Repeater {
        model: ch.options
        Item {
          required property var modelData
          readonly property bool chosen: ch.current === modelData.id
          implicitWidth: word.implicitWidth
          implicitHeight: Style.space(26)
          Text {
            id: word
            text: parent.modelData.label
            color: parent.chosen ? root.accent : root.muted
            font.family: root.family; font.pixelSize: Style.space(13); font.weight: parent.chosen ? Font.DemiBold : Font.Normal
            topPadding: Style.space(3)
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: 160 } }
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: word.bottom; anchors.topMargin: Style.space(2)
            width: 4; height: 4; radius: 2; color: root.accent; opacity: parent.chosen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
          }
          MouseArea { anchors.fill: parent; anchors.margins: -Style.space(3); cursorShape: Qt.PointingHandCursor; onClicked: ch.picked(parent.modelData.id) }
        }
      }
    }
  }

  component ToggleRow: Item {
    id: tr
    property string label: ""
    property string sub: ""
    property bool on: false
    signal toggled(bool next)
    width: parent ? parent.width : 0
    implicitHeight: Math.max(trCol.implicitHeight, Style.space(26))
    Column {
      id: trCol
      anchors.left: parent.left; anchors.right: trSwitch.left; anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)
      Label { text: tr.label }
      Caption { text: tr.sub; visible: text !== ""; width: parent.width; wrapMode: Text.WordWrap }
    }
    Switch { id: trSwitch; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: tr.on; onToggled: function(next) { tr.toggled(next) } }
  }

  component Chips: Flow {
    id: chips
    property var options: []        // [{id, label}]
    property string current: ""
    signal picked(string id)
    width: parent ? parent.width : 0
    spacing: Style.space(6)
    Repeater {
      model: chips.options
      Rectangle {
        required property var modelData
        readonly property bool chosen: chips.current === modelData.id
        width: chipText.implicitWidth + Style.space(22)
        height: Style.space(28)
        radius: height / 2
        color: chosen ? root.accent : chipMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14) : root.wash
        Behavior on color { ColorAnimation { duration: 140 } }
        Text {
          id: chipText
          anchors.centerIn: parent
          text: parent.modelData.label
          color: parent.chosen ? root.ink : root.fg
          font.family: root.family; font.pixelSize: Style.space(12); font.weight: parent.chosen ? Font.DemiBold : Font.Normal
          renderType: Text.NativeRendering
        }
        MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chips.picked(parent.modelData.id) }
      }
    }
  }

  // ================================================================ drawer
  Motion.PopupPanel {
    id: popup
    anchorItem: icon
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    padding: 0
    contentWidth: popup.fittedContentWidth(Style.space(620))
    contentHeight: popup.fittedContentHeight(Math.max(nav.implicitHeight, detail.implicitHeight + Style.space(48)), Style.space(820))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!dy) return
        var ids = root.pages.map(function(p) { return p.id })
        root.page = ids[Math.max(0, Math.min(ids.length - 1, ids.indexOf(root.page) + dy))]
      }
    }

    Item {
      width: parent.width
      height: parent.height

      // ---- nav
      Column {
        id: nav
        width: Style.space(176)
        height: parent.height
        topPadding: Style.space(24)
        leftPadding: Style.space(12)
        rightPadding: Style.space(12)
        spacing: Style.space(4)
        Text {
          text: "Studio"
          leftPadding: Style.space(10)
          bottomPadding: Style.space(14)
          color: root.fg; font.family: root.family; font.pixelSize: Style.space(20); font.weight: Font.Light
          renderType: Text.NativeRendering
        }
        Repeater {
          model: root.pages
          Rectangle {
            required property var modelData
            readonly property bool chosen: root.page === modelData.id
            width: nav.width - nav.leftPadding - nav.rightPadding
            height: Style.space(36)
            radius: Style.space(10)
            color: chosen ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : navMouse.containsMouse ? root.wash : "transparent"
            Behavior on color { ColorAnimation { duration: 140 } }
            Row {
              anchors.verticalCenter: parent.verticalCenter
              x: Style.space(10)
              spacing: Style.space(10)
              Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.glyph; color: chosen ? root.fg : root.muted; font.family: Style.font.family; font.pixelSize: Style.space(15) }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: chosen ? root.fg : root.muted
                font.family: root.family; font.pixelSize: Style.space(13); font.weight: chosen ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering
              }
            }
            MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.page = modelData.id }
          }
        }
      }
      Rectangle { x: nav.width; width: 1; height: parent.height; color: root.hair }

      // ---- detail
      Flickable {
        id: detailFlick
        x: nav.width + 1
        width: parent.width - nav.width - 1
        height: parent.height
        contentHeight: detail.implicitHeight + Style.space(48)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: detail
          x: Style.space(26)
          y: Style.space(24)
          width: detailFlick.width - Style.space(52)
          spacing: Style.space(12)

          // ================= Glass
          PageHead {
            visible: root.page === "glass"
            title: "Glass"
            sub: root.glass.enabled === false ? "Off · windows are solid"
              : (root.glassPresets.filter(function(p) { return p.id === root.glassPreset })[0] || { name: "Custom" }).name + " · applied"
            on: root.glass.enabled !== false
            onToggled: function(next) { root.glassSet("enabled", next) }
          }
          Section { visible: root.page === "glass"; text: "Presets" }
          Chips {
            visible: root.page === "glass"
            options: root.glassPresets.map(function(p) { return { id: p.id, label: p.name } })
            current: root.glassPreset
            onPicked: function(id) { root.glassUsePreset(id) }
          }
          Section { visible: root.page === "glass"; text: "Windows" }
          Fader { visible: root.page === "glass"; label: "Focused apps"; from: 0.4; to: 1; value: Number(root.glass.active || 1); onCommitted: function(v) { root.glassSet("active", v.toFixed(2)) } }
          Fader { visible: root.page === "glass"; label: "Unfocused apps"; from: 0.4; to: 1; value: Number(root.glass.inactive || 1); onCommitted: function(v) { root.glassSet("inactive", v.toFixed(2)) } }
          Fader { visible: root.page === "glass"; label: "Focused browser"; from: 0.4; to: 1; value: Number(root.glass.browser_active || 1); onCommitted: function(v) { root.glassSet("browser_active", v.toFixed(2)) } }
          Fader { visible: root.page === "glass"; label: "Unfocused browser"; from: 0.4; to: 1; value: Number(root.glass.browser_inactive || 1); onCommitted: function(v) { root.glassSet("browser_inactive", v.toFixed(2)) } }
          Section { visible: root.page === "glass"; text: "Texture" }
          Fader { visible: root.page === "glass"; label: "Blur"; from: 1; to: 12; step: 1; factor: 1; unit: "px"; tint: root.warm; value: Number(root.glass.size || 6); onCommitted: function(v) { root.glassSet("size", Math.round(v)) } }
          Fader { visible: root.page === "glass"; label: "Vibrancy"; from: 0; to: 0.5; tint: root.warm; value: Number(root.glass.vibrancy || 0); onCommitted: function(v) { root.glassSet("vibrancy", v.toFixed(2)) } }
          Fader { visible: root.page === "glass"; label: "Contrast"; from: 0.5; to: 1.5; factor: 1; decimals: 2; unit: "×"; tint: root.warm; value: Number(root.glass.contrast || 1); onCommitted: function(v) { root.glassSet("contrast", v.toFixed(2)) } }
          Fader { visible: root.page === "glass"; label: "Brightness"; from: 0.6; to: 1.2; factor: 1; decimals: 2; unit: "×"; tint: root.warm; value: Number(root.glass.brightness || 1); onCommitted: function(v) { root.glassSet("brightness", v.toFixed(2)) } }
          ToggleRow {
            visible: root.page === "glass"
            label: "Keep light themes readable"
            sub: "On light themes, windows stay nearly solid whatever the sliders say."
            on: root.glass.light_readable !== false
            onToggled: function(next) { root.glassSet("light_readable", next) }
          }

          // ================= Depth
          PageHead {
            visible: root.page === "depth"
            title: "Depth"
            sub: root.depth.enabled === false ? "Off · windows sit flat" : root.depthRaised ? "Windows raised off the screen" : "Windows pressed into the screen"
            on: root.depth.enabled !== false
            onToggled: function(next) { if (next) root.depthMode(root.depthRaised ? "raised" : "recessed"); else root.depthMode("flat") }
          }
          Choice {
            visible: root.page === "depth"
            label: "Style"
            options: [{ id: "recessed", label: "Recessed" }, { id: "raised", label: "Raised" }]
            current: root.depthRaised ? "raised" : "recessed"
            onPicked: function(id) { root.depthMode(id) }
          }
          Row {
            visible: root.page === "depth"
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: root.depthLooks
              Rectangle {
                required property var modelData
                required property int index
                readonly property bool chosen: root.depthProf.look === modelData.id
                width: (detail.width - Style.space(16)) / 3
                height: Style.space(86)
                radius: Style.space(14)
                color: lookMouse.containsMouse ? root.wash : "transparent"
                border.width: chosen ? 1.5 : 0
                border.color: root.accent
                Rectangle {
                  id: swatch
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: Style.space(12)
                  width: Style.space(58); height: Style.space(38); radius: Style.space(9)
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
                  // Raised looks lift more with each step; recessed sink more.
                  Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    gradient: Gradient {
                      GradientStop { position: 0; color: root.depthRaised ? Qt.rgba(1, 1, 1, 0.10 + 0.06 * index) : Qt.rgba(0, 0, 0, 0.18 + 0.14 * index) }
                      GradientStop { position: 0.6; color: "transparent" }
                      GradientStop { position: 1; color: root.depthRaised ? Qt.rgba(0, 0, 0, 0.14 + 0.08 * index) : Qt.rgba(1, 1, 1, 0.04 + 0.03 * index) }
                    }
                  }
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: swatch.bottom; anchors.topMargin: Style.space(8)
                  text: modelData.label
                  color: chosen ? root.fg : root.muted
                  font.family: root.family; font.pixelSize: Style.space(12); font.weight: chosen ? Font.DemiBold : Font.Normal
                  renderType: Text.NativeRendering
                }
                MouseArea { id: lookMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.depthLook(modelData.id) }
              }
            }
          }
          Fader {
            visible: root.page === "depth"
            label: "Intensity"
            from: 0; to: 100; step: 1; factor: 1; unit: ""
            tint: root.warm
            enabledLook: root.depthProf.look !== "custom"
            value: Number(root.depthProf.intensity === undefined ? 50 : root.depthProf.intensity)
            onCommitted: function(v) { root.depthSet("intensity", Math.round(v), true) }
          }
          Choice {
            visible: root.page === "depth"
            label: "Tuning for"
            options: [{ id: "light", label: "Light themes" }, { id: "dark", label: "Dark themes" }]
            current: root.profile
            onPicked: function(id) { root.depthProfile = id }
          }
          Section { visible: root.page === "depth"; text: root.depthProf.look === "custom" ? "Details · custom" : "Details" }
          Fader { visible: root.page === "depth"; label: root.depthRaised ? "Height" : "Depth"; value: Number(root.depthProf.win_depth || 0); onCommitted: function(v) { root.depthSet("win_depth", v.toFixed(2), true) } }
          Fader { visible: root.page === "depth"; label: root.depthRaised ? "Shadow softness" : "Softness"; from: 2; to: 30; step: 1; factor: 1; unit: "px"; value: Number(root.depthProf.win_soft || 10); onCommitted: function(v) { root.depthSet("win_soft", Math.round(v), true) } }
          Fader { visible: root.page === "depth"; label: "Light from above"; value: Number(root.depthProf.win_light || 0); onCommitted: function(v) { root.depthSet("win_light", v.toFixed(2), true) } }
          Fader { visible: root.page === "depth"; label: root.depthRaised ? "Top sheen" : "Lower highlight"; value: Number(root.depthProf.win_lip || 0); onCommitted: function(v) { root.depthSet("win_lip", v.toFixed(2), true) } }

          // ================= Tricky Tiles
          PageHead {
            visible: root.page === "tiles"
            title: "Tricky Tiles"
            sub: "Spring switching for windows and workspaces"
            on: root.tiles.enabled !== false
            onToggled: function(next) { root.tilesSet("enabled", next) }
          }
          Section { visible: root.page === "tiles"; text: "Feel" }
          Chips {
            visible: root.page === "tiles"
            options: root.tilesOrder.filter(function(id) { return !!root.tilesPresets[id] }).map(function(id) { return { id: id, label: root.tilesPresets[id].label || id } })
            current: root.tiles.preset || ""
            onPicked: function(id) { root.tilesUsePreset(id) }
          }
          // The spring this feel makes: a settle curve from duration and bounce.
          Shape {
            id: curve
            visible: root.page === "tiles"
            width: detail.width
            height: Style.space(56)
            preferredRendererType: Shape.CurveRenderer
            readonly property real bounce: Number(root.tiles.bounce || 0) / 40
            readonly property real dur: (Number(root.tiles.duration || 300) - 150) / 350
            readonly property var points: {
              var pts = [], n = 60, w = width, h = height - 6
              var zeta = 1 - bounce * 0.75, omega = 9 + 6 * (1 - dur)
              for (var i = 0; i <= n; i++) {
                var t = i / n, wd = omega * Math.sqrt(Math.max(0.0001, 1 - zeta * zeta))
                var p = 1 - Math.exp(-zeta * omega * t) * (Math.cos(wd * t) + (zeta * omega / wd) * Math.sin(wd * t))
                pts.push(Qt.point(1 + t * (w - 2), 3 + h - Math.max(-0.2, Math.min(1.35, p)) * h * 0.72))
              }
              return pts
            }
            ShapePath { strokeColor: root.hair; strokeWidth: 1; fillColor: "transparent"; startX: 0; startY: curve.height - 3; PathLine { x: curve.width; y: curve.height - 3 } }
            ShapePath {
              strokeColor: root.warm; strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
              PathPolyline { path: curve.points }
            }
          }
          Fader { visible: root.page === "tiles"; label: "Duration"; from: 150; to: 500; step: 10; factor: 1; unit: " ms"; value: Number(root.tiles.duration || 300); onCommitted: function(v) { root.tilesSet("duration", Math.round(v)) } }
          Fader { visible: root.page === "tiles"; label: "Bounce"; from: 0; to: 40; step: 1; factor: 1; value: Number(root.tiles.bounce || 0); onCommitted: function(v) { root.tilesSet("bounce", Math.round(v)) } }
          Fader { visible: root.page === "tiles"; label: "Travel"; from: 0; to: 100; step: 5; factor: 1; value: Number(root.tiles.travel || 0); onCommitted: function(v) { root.tilesSet("travel", Math.round(v)) } }
          Rectangle { visible: root.page === "tiles"; width: parent.width; height: 1; color: root.hair }
          Choice {
            visible: root.page === "tiles"
            label: "Swipes"
            options: [{ id: "off", label: "Off" }, { id: "3", label: "3 fingers" }, { id: "4", label: "4 fingers" }]
            current: root.tiles.swipes === false ? "off" : String(root.tiles.fingers || "3")
            onPicked: function(id) {
              if (id === "off") { root.tilesSet("swipes", false); return }
              if (root.tiles.swipes === false) root.tilesSet("swipes", true)
              root.tilesSet("fingers", id)
            }
          }
          Choice {
            visible: root.page === "tiles" && root.tiles.swipes !== false
            label: "Sideways"
            options: [{ id: "windows", label: "Windows" }, { id: "workspaces", label: "Workspaces" }, { id: "off", label: "Off" }]
            current: String(root.tiles.swipe_horizontal || "windows")
            onPicked: function(id) { root.tilesSet("swipe_horizontal", id) }
          }
          Choice {
            visible: root.page === "tiles" && root.tiles.swipes !== false
            label: "Tracking"
            options: [{ id: "step", label: "One per swipe" }, { id: "follow", label: "Follow fingers" }]
            current: String(root.tiles.tracking || "step")
            onPicked: function(id) { root.tilesSet("tracking", id) }
          }
          Fader { visible: root.page === "tiles" && root.tiles.swipes !== false; label: "Sensitivity"; from: 50; to: 200; step: 5; factor: 1; value: Number(root.tiles.sensitivity || 100); onCommitted: function(v) { root.tilesSet("sensitivity", Math.round(v)) } }
          ToggleRow { visible: root.page === "tiles"; label: "Wrap around"; on: root.tiles.wrap !== false; onToggled: function(next) { root.tilesSet("wrap", next) } }
          ToggleRow { visible: root.page === "tiles"; label: "Fade focus"; on: root.tiles.focus_fade !== false; onToggled: function(next) { root.tilesSet("focus_fade", next) } }
          ToggleRow { visible: root.page === "tiles"; label: "Preview windows"; sub: "Show the carousel's neighbours while you swipe"; on: root.tiles.preview_windows !== false; onToggled: function(next) { root.tilesSet("preview_windows", next) } }
          Caption {
            visible: root.page === "tiles"
            text: "More: workspace axis, power saver, share codes  ›"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openFull("io.github.denonmaryland.tricky-tiles") }
          }

          // ================= Display
          PageHead { visible: root.page === "display"; title: "Display"; sub: root.display; hasSwitch: false }
          Fader {
            visible: root.page === "display"
            label: "Brightness"
            from: 0.01; to: 1; step: 0.01
            tint: root.warm
            value: root.brightness
            onCommitted: function(v) { root.setBrightness(v) }
          }
          ToggleRow {
            visible: root.page === "display"
            label: "Night light"
            sub: "Warmer screen for the evening"
            on: root.nightOn
            onToggled: function(next) { root.nightOn = next; Quickshell.execDetached(["omarchy", "toggle", "nightlight"]) }
          }
          Caption {
            visible: root.page === "display"
            text: "Scale, resolution and arrangement  ›"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openFull("omarchy.monitor") }
          }
        }
      }
    }
  }
}
