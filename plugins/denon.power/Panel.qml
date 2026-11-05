import "../denon.bar/panels" as Motion
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  // Glass surfaces: calm sentence-case taglines instead of tracked capitals.
  function glassSentence(v) { var t = String(v || ""); return t.length ? t.charAt(0).toUpperCase() + t.slice(1).toLowerCase() : t }

  moduleName: "inferna.power"
  ipcTarget: "inferna.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    if (root.previewLow) return 0.14
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  // Charging must be obvious at a glance: plugged in tints the bar icon and the
  // panel in the theme accent; actively charging adds a breathing icon, a
  // "Charging" badge and current flowing through the battery bar.
  property bool previewCharging: false   // IPC: inferna-shell inferna.power previewCharging
  property bool previewLow: false         // IPC: inferna-shell inferna.power previewLow
  readonly property bool pluggedIn: previewCharging || (batteryPresent && !UPower.onBattery)
  readonly property bool chargingNow: previewCharging || charging
  readonly property color chargeColor: Commons.Color.accent

  // Every state shares one look: battery = frosted, low = urgent, plugged in = accent.
  readonly property bool lowBattery: previewLow || !pluggedIn && batteryPresent && batteryFraction <= 0.2
  readonly property color stateColor: pluggedIn ? chargeColor : lowBattery ? Commons.Color.urgent : (bar ? bar.foreground : Commons.Color.foreground)
  readonly property color floodColor: (pluggedIn || lowBattery) ? stateColor : Qt.rgba(stateColor.r, stateColor.g, stateColor.b, 0.17)
  readonly property color floodInk: (pluggedIn || lowBattery) ? Commons.Color.background : (bar ? bar.foreground : Commons.Color.foreground)

  readonly property color batteryFillColor: {
    if (root.pluggedIn) return root.chargeColor
    return root.bar ? root.bar.foreground : Commons.Color.foreground
  }

  function chargeLine() {
    var bits = ["Plugged in"]
    if (root.chargeThresholdActive) bits.push("holding at limit")
    else if (root.batteryFull) bits.push("fully charged")
    else {
      if (root.batteryInfo.time) bits.push("full in " + root.batteryInfo.time)
      if (root.batteryInfo.rate) bits.push(root.batteryInfo.rate + " in")
    }
    return bits.join(" · ")
  }

  function floodSubline() {
    if (!root.pluggedIn) {
      var left = root.batteryInfo.time ? root.batteryInfo.time + " left" : ""
      return root.lowBattery ? (left ? left + " · plug in soon" : "Plug in soon") : left
    }
    if (root.chargeThresholdActive) return root.batteryInfo.threshold ? "limit " + root.batteryInfo.threshold : ""
    if (root.batteryFull) return "Fully charged"
    return root.batteryInfo.time ? "Full in " + root.batteryInfo.time : ""
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["inferna-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "inferna.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    function previewLow() { root.previewLow = !root.previewLow; return root.previewLow ? "low preview on" : "low preview off" }
    function previewCharging() { root.previewCharging = !root.previewCharging; return root.previewCharging ? "preview on" : "preview off" }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["inferna-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["inferna-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["inferna-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    // Horizontal bar: a capsule replaces the glyph in every state — frosted
    // "▭ 82%" on battery, urgent when low, solid accent "󱐋 89%" when plugged in.
    readonly property bool capsule: !vertical
    slotSize: capsule
      ? capsuleMetrics.width + Style.space(26)
      : Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    iconComponent: capsule ? chargeCapsule : null
    tooltipText: (root.chargingNow ? "Charging · " : root.pluggedIn ? "Plugged in · " : "On battery · ") + Math.round(root.batteryFraction * 100) + "%"
    active: root.pluggedIn && !capsule
    useActiveColor: true
    activeColor: root.chargeColor

    TextMetrics {
      id: capsuleMetrics
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption + 1
      font.weight: Font.Bold
      text: "▭ 100%"
    }

    Component {
      id: chargeCapsule
      Item {
        Rectangle {
          anchors.centerIn: parent
          height: Style.space(17)
          width: capsuleRow.implicitWidth + Style.space(12)
          radius: height / 2
          readonly property bool solid: root.pluggedIn || root.lowBattery
          readonly property color ink: solid ? Commons.Color.background : root.bar.foreground
          color: solid ? root.stateColor : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.13)
          Behavior on color { ColorAnimation { duration: 220 } }
          Row {
            id: capsuleRow
            anchors.centerIn: parent
            spacing: Style.space(3)
            // Mini battery (not plugged in): outline + level fill.
            Item {
              visible: !root.pluggedIn
              width: Style.space(14)
              height: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              Rectangle {
                width: parent.width - Style.space(2)
                height: parent.height
                radius: Style.space(2)
                color: "transparent"
                border.width: 1
                border.color: capsuleRow.parent.ink
                Rectangle {
                  x: Style.space(2); y: Style.space(2)
                  height: parent.height - Style.space(4)
                  width: Math.max(Style.space(1.5), (parent.width - Style.space(4)) * Math.max(0, Math.min(1, root.batteryFraction)))
                  radius: Style.space(1)
                  color: capsuleRow.parent.ink
                }
              }
              Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(1.5); height: Style.space(3); radius: width / 2
                color: capsuleRow.parent.ink
              }
            }
            Text {
              id: capsuleBolt
              visible: root.pluggedIn
              text: "󱐋"
              color: Commons.Color.background
              font.family: Style.font.family
              font.pixelSize: Style.font.caption + 1
              anchors.verticalCenter: parent.verticalCenter
              // Current flowing in: the bolt pulses; the capsule stays solid.
              SequentialAnimation on opacity {
                running: root.chargingNow && !root.batteryFull
                loops: Animation.Infinite
                onRunningChanged: if (!running) capsuleBolt.opacity = 1
                NumberAnimation { from: 1.0; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
              }
            }
            Text {
              text: Math.round(root.batteryFraction * 100) + "%"
              color: capsuleRow.parent.ink
              font: capsuleMetrics.font
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
    }

    // Vertical bars keep the glyph; it breathes in the accent while charging.
    SequentialAnimation on opacity {
      running: !button.capsule && root.chargingNow && !root.batteryFull
      loops: Animation.Infinite
      onRunningChanged: if (!running) button.opacity = 1
      NumberAnimation { from: 1.0; to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.55; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
    }
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else if (!Motion.PanelMotion.commitHover(root)) root.toggle()
    }
  }

  Motion.PopupPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Flood hero: the card fills to the charge level ----------
        // Direction B-A: the charge level floods the hero in the theme accent,
        // left to right, so being on the charger reads from across the room.
        // The labels are drawn twice — foreground on the track, background on
        // the fill (clipped to the fill width) — so they stay legible at any level.
        Item {
          id: flood
          width: parent.width
          height: Style.space(132)
          readonly property real level: Math.max(0, Math.min(1, root.batteryFraction))
          readonly property real fillWidth: level > 0 ? Math.max(radiusPx * 2, width * level) : 0
          readonly property real radiusPx: Style.space(12)

          Rectangle {
            anchors.fill: parent
            radius: flood.radiusPx
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.07)
          }

          Item {
            id: floodFill
            width: flood.fillWidth
            height: parent.height
            clip: true
            Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

            Rectangle {
              width: flood.width
              height: parent.height
              radius: flood.radiusPx
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.floodColor }
                GradientStop { position: 1.0; color: root.pluggedIn ? Qt.lighter(root.floodColor, 1.18) : root.floodColor }
              }
            }
            // Current flowing in: a soft sheen sweeps through the fill.
            Rectangle {
              id: floodSheen
              visible: root.chargingNow && !root.batteryFull
              width: Style.space(70)
              height: parent.height
              x: -width
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
              }
              NumberAnimation on x {
                running: floodSheen.visible && root.opened
                loops: Animation.Infinite
                from: -floodSheen.width
                to: floodFill.width
                duration: 2200
                easing.type: Easing.InOutQuad
              }
            }
          }

          FloodLabels { anchors.fill: parent; ink: root.bar.foreground }
          Item {
            width: floodFill.width
            height: parent.height
            clip: true
            FloodLabels { width: flood.width; height: flood.height; ink: root.floodInk }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Motion.GlassTile {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          foreground: root.bar.foreground
          implicitHeight: statsRow.implicitHeight + Style.space(20)

        Row {
          id: statsRow
          x: Style.space(12)
          y: Style.space(10)
          width: parent.width - Style.space(24)
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }
        }

        // ---------- Power profile picker ----------
        Motion.GlassSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          Motion.GlassSection {
            text: Motion.PanelMotion.tide ? "Power profile" : "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Motion.GlassTrack {
            width: parent.width
            foreground: root.bar.foreground

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(2)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(1)
                bordered: false
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
          }
        }
      }
    }
  }

  component FloodLabels: Item {
    property color ink: root.bar.foreground

    Row {
      x: Style.space(16)
      y: Style.space(14)
      spacing: Style.space(8)
      Text {
        visible: root.pluggedIn
        text: "󱐋"
        color: ink
        font.family: Style.font.family
        font.pixelSize: Style.font.body + 1
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        readonly property string state: root.chargingNow ? "CHARGING" : root.chargeThresholdActive ? "HOLDING AT LIMIT" : root.pluggedIn ? "PLUGGED IN" : root.lowBattery ? "LOW BATTERY" : "ON BATTERY"
        text: Motion.PanelMotion.tide ? state.charAt(0) + state.slice(1).toLowerCase() : state
        color: ink
        font.family: root.bar.fontFamily
        font.pixelSize: Motion.PanelMotion.tide ? Style.space(13) : Style.font.bodySmall + 1
        font.weight: Motion.PanelMotion.tide ? Font.Medium : Font.Bold
        font.letterSpacing: Motion.PanelMotion.tide ? 0 : 0.6
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: root.floodSubline()
        color: Qt.rgba(ink.r, ink.g, ink.b, 0.72)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall + 1
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      x: Style.space(14)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(4)
      text: Math.round(root.batteryFraction * 100) + "%"
      color: ink
      font.family: root.bar.fontFamily
      font.pixelSize: Math.round(Style.font.displayLarge * 2.4)
      font.weight: Motion.PanelMotion.tide ? Font.ExtraLight : Font.ExtraBold
      font.letterSpacing: -2
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
