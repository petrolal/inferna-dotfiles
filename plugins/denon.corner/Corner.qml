import "../denon.bar/panels" as Motion
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Control corner (Pebble Shell, Paper "Fan" iteration). A quarter circle
// fans out of the rail's bottom corner: brightness, volume and microphone
// as concentric arcs you drag along, the everyday toggles on an inner arc,
// and the battery in the corner. Push the pointer into the bottom-left
// corner (denon.shell's hot corner) or use the grip on the rail.
// Left click toggles; right click a toggle (or tap a label) for the full
// panel of that tool, which stays loaded but tucked off the rail.
Panel {
  id: root
  moduleName: "denon.corner"
  ipcTarget: "denon.corner"
  implicitWidth: grip.implicitWidth
  implicitHeight: grip.implicitHeight

  readonly property color fg: Commons.Color.popups.text
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color hair: Qt.rgba(fg.r, fg.g, fg.b, 0.16)
  readonly property color accent: Commons.Color.accent
  readonly property color warm: Qt.tint(Commons.Color.accent, Qt.rgba(1, 0.75, 0.3, 0.55))
  readonly property color knobInk: Commons.Color.popups.background
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property real fanR: Style.space(440)

  // ---------------------------------------------------------------- state
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  PwObjectTracker { objects: [root.sink, root.source].filter(function(x) { return !!x }) }
  readonly property real volume: sink && sink.audio ? Math.min(1, sink.audio.volume) : 0
  readonly property bool volumeMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property real mic: source && source.audio ? Math.min(1, source.audio.volume) : 0
  readonly property bool micMuted: source && source.audio ? source.audio.muted : false
  property real brightness: 0.5
  property real brightnessDraft: -1

  readonly property var battery: UPower.displayDevice
  readonly property real batteryLevel: {
    var p = battery ? battery.percentage : 0
    return p > 1 ? p / 100 : p
  }
  readonly property bool charging: battery ? battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged : false
  readonly property string timeLeft: {
    var s = battery ? (charging ? battery.timeToFull : battery.timeToEmpty) : 0
    if (!s || s <= 0) return ""
    var h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60)
    return (h > 0 ? h + " h " : "") + m + " m"
  }

  property bool wifiOn: true
  property bool btOn: true
  property bool nightOn: false
  property bool dndOn: false
  property bool awakeOn: false
  property string profile: "balanced"

  onOpenedChanged: if (opened) refresh()
  Timer { interval: 4000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  function refresh() { if (!stateRead.running) stateRead.running = true }
  function run(cmd) { Quickshell.execDetached(cmd); refreshSoon.restart() }
  Timer { id: refreshSoon; interval: 450; onTriggered: root.refresh() }
  function openFull(target) { root.close(); Quickshell.execDetached(["inferna-shell", target, "open"]) }

  Process {
    id: stateRead
    command: ["sh", "-c",
      "echo wifi=$(nmcli radio wifi 2>/dev/null);" +
      "echo bt=$(bluetoothctl show 2>/dev/null | sed -n 's/.*Powered: //p' | head -1);" +
      "echo night=$(inferna toggle nightlight --status 2>/dev/null | grep -o '\"enabled\":[a-z]*' | cut -d: -f2);" +
      "echo dnd=$(inferna-shell notifications isDnd 2>/dev/null);" +
      "echo awake=$(test -e \"$HOME/.local/state/inferna/indicators/stay-awake\" && echo on || echo off);" +
      "echo profile=$(powerprofilesctl get 2>/dev/null);" +
      "echo bright=$(brightnessctl -m 2>/dev/null | head -1 | cut -d, -f4 | tr -d '%')"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var kv = lines[i].split("="), k = kv[0], v = (kv[1] || "").trim()
          if (k === "wifi") root.wifiOn = v === "enabled"
          else if (k === "bt") root.btOn = v === "yes"
          else if (k === "night") root.nightOn = v === "true"
          else if (k === "dnd") root.dndOn = v === "on"
          else if (k === "awake") root.awakeOn = v === "on"
          else if (k === "profile" && v) root.profile = v
          else if (k === "bright" && v !== "" && root.brightnessDraft < 0) root.brightness = Math.max(0, Math.min(1, Number(v) / 100))
        }
      }
    }
  }

  function setBrightness(f) {
    brightness = Math.max(0.01, Math.min(1, f))
    var mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var cmd = ["inferna-brightness-display", "--no-osd"]
    if (mon) cmd = cmd.concat(["--monitor", mon])
    Quickshell.execDetached(cmd.concat([Math.round(brightness * 100) + "%"]))
  }
  function setVolume(f) { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, f)) } }
  function setMic(f) { if (source && source.audio) source.audio.volume = Math.max(0, Math.min(1, f)) }
  function nextProfile() {
    var order = ["power-saver", "balanced", "performance"]
    var next = order[(order.indexOf(profile) + 1) % order.length]
    profile = next
    run(["powerprofilesctl", "set", next])
  }
  readonly property string profileLabel: profile === "power-saver" ? "Saver" : profile === "performance" ? "Performance" : "Balanced"

  // ---------------------------------------------------------------- rail grip
  WidgetButton {
    id: grip
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedHeight: Style.space(38)
    tooltipText: "Control corner · " + Math.round(root.batteryLevel * 100) + "%" + (root.timeLeft ? " · " + root.timeLeft : "")
    onPressed: function(buttonCode) {
      if (!Motion.PanelMotion.commitHover(root)) root.toggle()
    }
    Item {
      anchors.centerIn: parent
      width: Style.space(28); height: width
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: root.hair; strokeWidth: Style.space(2.5); fillColor: "transparent"
          PathAngleArc { centerX: Style.space(14); centerY: Style.space(14); radiusX: Style.space(11.5); radiusY: Style.space(11.5); startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
          strokeColor: root.batteryLevel <= 0.2 && !root.charging ? Commons.Color.urgent : root.accent
          strokeWidth: Style.space(2.5); fillColor: "transparent"; capStyle: ShapePath.RoundCap
          PathAngleArc { centerX: Style.space(14); centerY: Style.space(14); radiusX: Style.space(11.5); radiusY: Style.space(11.5); startAngle: -90; sweepAngle: 360 * root.batteryLevel }
        }
      }
      Text {
        anchors.centerIn: parent
        text: root.charging ? "󱐋" : "󰒓"
        color: grip.foreground
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
    }
  }

  // ---------------------------------------------------------------- the fan
  component Ring: Shape {
    id: ring
    property real radius: 300
    property real value: 0
    property color tint: root.accent
    property real weight: 5
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: root.hair; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: 0; centerY: root.fanR; radiusX: ring.radius; radiusY: ring.radius; startAngle: -90; sweepAngle: 90 }
    }
    ShapePath {
      strokeColor: ring.tint; strokeWidth: ring.weight; fillColor: "transparent"; capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: 0; centerY: root.fanR; radiusX: ring.radius; radiusY: ring.radius; startAngle: -90; sweepAngle: Math.max(0.5, 90 * ring.value) }
    }
  }
  component Knob: Rectangle {
    property real radius2: 300
    property real value: 0
    readonly property real theta: value * Math.PI / 2
    width: Style.space(16); height: width; radius: width / 2
    color: root.fg
    x: radius2 * Math.sin(theta) - width / 2
    y: root.fanR - radius2 * Math.cos(theta) - height / 2
  }
  component Level: Item {
    id: level
    property string glyph: ""
    property real value: 0
    property color tint: root.fg
    property string target: ""
    implicitWidth: levelRow.implicitWidth
    implicitHeight: levelRow.implicitHeight
    Row {
      id: levelRow
      spacing: Style.space(6)
      Text { anchors.verticalCenter: parent.verticalCenter; text: level.glyph; color: level.tint; font.family: Style.font.family; font.pixelSize: Style.space(14) }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(level.value * 100)
        color: level.tint
        font.family: root.family
        font.pixelSize: Style.space(22)
        font.weight: Font.ExtraLight
        renderType: Text.NativeRendering
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (level.target) root.openFull(level.target) }
  }
  component Toggle: Rectangle {
    id: toggle
    property string glyph: ""
    property bool on: false
    property string tip: ""
    property real angle: 0
    signal flip()
    signal more()
    readonly property real ringR: Style.space(262)
    width: Style.space(46); height: width; radius: width / 2
    x: ringR * Math.sin(angle * Math.PI / 180) - width / 2
    y: root.fanR - ringR * Math.cos(angle * Math.PI / 180) - height / 2
    color: on ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, toggleMouse.containsMouse ? 0.16 : 0.10)
    border.width: on ? 0 : 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
    scale: toggleMouse.pressed ? 0.92 : 1
    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }
    Text {
      anchors.centerIn: parent
      text: toggle.glyph
      color: toggle.on ? root.knobInk : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.space(18)
    }
    MouseArea {
      id: toggleMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { if (mouse.button === Qt.RightButton) toggle.more(); else toggle.flip() }
    }
    PanelToolTip { visible: toggleMouse.containsMouse; text: toggle.tip; fontFamily: root.family }
  }

  Motion.PopupPanel {
    id: popup
    anchorItem: grip
    owner: root
    bar: root.bar
    open: root.opened
    shape: "fan"
    padding: 0
    focusTarget: keys
    contentWidth: root.fanR
    contentHeight: root.fanR

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Item {
      id: fan
      width: root.fanR
      height: root.fanR

      readonly property real rB: root.fanR - Style.space(40)
      readonly property real rV: root.fanR - Style.space(90)
      readonly property real rM: root.fanR - Style.space(140)
      readonly property real brightnessShown: root.brightnessDraft >= 0 ? root.brightnessDraft : root.brightness

      Ring { radius: fan.rB; value: fan.brightnessShown; tint: root.warm }
      Ring { radius: fan.rV; value: root.volume; tint: root.volumeMuted ? root.muted : root.accent }
      Ring { radius: fan.rM; value: root.mic; tint: root.micMuted ? root.muted : root.fg; weight: 3 }
      Knob { radius2: fan.rB; value: fan.brightnessShown }
      Knob { radius2: fan.rV; value: root.volume }
      Knob { radius2: fan.rM; value: root.mic; width: Style.space(12) }

      // Drag along an arc: pick the ring by distance from the corner, the
      // value by the angle.
      MouseArea {
        id: arcs
        anchors.fill: parent
        property string ring: ""
        function polar(mx, my) {
          var dx = mx, dy = root.fanR - my
          return { d: Math.sqrt(dx * dx + dy * dy), f: Math.max(0, Math.min(1, Math.atan2(dx, dy) / (Math.PI / 2))) }
        }
        function pick(d) {
          var tol = Style.space(24)
          if (Math.abs(d - fan.rB) < tol) return "b"
          if (Math.abs(d - fan.rV) < tol) return "v"
          if (Math.abs(d - fan.rM) < tol) return "m"
          return ""
        }
        function apply(p) {
          if (ring === "b") root.brightnessDraft = p.f
          else if (ring === "v") root.setVolume(p.f)
          else if (ring === "m") root.setMic(p.f)
        }
        onPressed: function(mouse) {
          var p = polar(mouse.x, mouse.y)
          ring = pick(p.d)
          if (!ring) { mouse.accepted = false; return }
          apply(p)
        }
        onPositionChanged: function(mouse) { if (pressed && ring) apply(polar(mouse.x, mouse.y)) }
        onReleased: {
          if (ring === "b" && root.brightnessDraft >= 0) { root.setBrightness(root.brightnessDraft); root.brightnessDraft = -1 }
          ring = ""
        }
        onWheel: function(wheel) {
          var p = polar(wheel.x, wheel.y), r = pick(p.d), step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
          if (r === "b") root.setBrightness(root.brightness + step)
          else if (r === "v") root.setVolume(root.volume + step)
          else if (r === "m") root.setMic(root.mic + step)
        }
      }

      Level { x: Style.space(14); y: root.fanR - fan.rB + Style.space(10); glyph: "󰃟"; value: fan.brightnessShown; tint: root.warm; target: "inferna.monitor" }
      Level { x: Style.space(14); y: root.fanR - fan.rV + Style.space(10); glyph: root.volumeMuted ? "󰝟" : "󰕾"; value: root.volume; tint: root.accent; target: "inferna.audio" }
      Level { x: Style.space(14); y: root.fanR - fan.rM + Style.space(8); glyph: root.micMuted ? "󰍭" : "󰍬"; value: root.mic; tint: root.fg; target: "inferna.audio" }

      Toggle { angle: 21; glyph: "󰖩"; on: root.wifiOn; tip: "Wi-Fi · right-click for networks"; onFlip: { root.wifiOn = !root.wifiOn; root.run(["nmcli", "radio", "wifi", root.wifiOn ? "on" : "off"]) } onMore: root.openFull("inferna.network") }
      Toggle { angle: 32; glyph: "󰂯"; on: root.btOn; tip: "Bluetooth · right-click for devices"; onFlip: { root.btOn = !root.btOn; root.run(["bluetoothctl", "power", root.btOn ? "on" : "off"]) } onMore: root.openFull("inferna.bluetooth") }
      Toggle { angle: 43; glyph: "󰖔"; on: root.nightOn; tip: "Night light"; onFlip: { root.nightOn = !root.nightOn; root.run(["inferna", "toggle", "nightlight"]) } onMore: root.openFull("inferna.monitor") }
      Toggle { angle: 54; glyph: "󰂛"; on: root.dndOn; tip: "Do not disturb"; onFlip: { root.dndOn = !root.dndOn; root.run(["inferna-toggle-notification-silencing"]) } onMore: root.openFull("inferna.notifications") }
      Toggle { angle: 65; glyph: "󰅶"; on: root.awakeOn; tip: "Keep awake"; onFlip: { root.awakeOn = !root.awakeOn; root.run(["inferna", "toggle", "idle", "toggle"]) } onMore: {} }
      Toggle { angle: 76; glyph: "󰇣"; on: false; tip: "Dropbox"; onFlip: root.openFull("inferna.dropbox"); onMore: root.openFull("inferna.dropbox") }

      // The battery, in the corner.
      Column {
        x: Style.space(22)
        y: root.fanR - Style.space(140)
        spacing: Style.space(2)
        Text {
          text: (root.charging ? "Charging" : "On battery") + (root.timeLeft ? " · " + root.timeLeft : "")
          color: root.muted; font.family: root.family; font.pixelSize: Style.space(12)
        }
        Text {
          text: Math.round(root.batteryLevel * 100) + "<span style='font-size:" + Style.space(22) + "px'>%</span>"
          textFormat: Text.StyledText
          color: root.batteryLevel <= 0.2 && !root.charging ? Commons.Color.urgent : root.fg
          font.family: root.family
          font.pixelSize: Style.space(56)
          font.weight: Font.ExtraLight
          font.letterSpacing: -2
          renderType: Text.NativeRendering
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openFull("inferna.power") }
        }
        Row {
          topPadding: Style.space(6)
          spacing: Style.space(16)
          Text {
            text: root.profileLabel
            color: root.accent; font.family: root.family; font.pixelSize: Style.space(12); font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); cursorShape: Qt.PointingHandCursor; onClicked: root.nextProfile() }
          }
          Item {
            implicitWidth: recordRow.implicitWidth
            implicitHeight: recordRow.implicitHeight
            Row {
              id: recordRow
              spacing: Style.space(6)
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Style.space(9); height: width; radius: width / 2; color: Commons.Color.urgent }
              Text { text: "Record"; color: root.fg; font.family: root.family; font.pixelSize: Style.space(12) }
            }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.close(); Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.global(\"snip:record\")"]) }
            }
          }
        }
      }
    }
  }
}
