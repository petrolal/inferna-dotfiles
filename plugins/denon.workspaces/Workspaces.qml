import "../denon.bar/panels" as Motion
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "inferna.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  // Pebble Shell rail (Paper "Fan" iteration): a recessed capsule track,
  // empty workspaces as dots, the focused one a tall accent pill with its
  // number. The chip below is that pill; rows spring between 16 and 50px.
  readonly property bool tideRail: root.vertical && Motion.PanelMotion.tide
  readonly property real trackPad: tideRail ? Style.space(7) : 0
  readonly property var ids: workspaceIds()
  readonly property int focusedIndex: Hyprland.focusedWorkspace ? ids.indexOf(Hyprland.focusedWorkspace.id) : -1

  // Depth plugin link (personal; not part of the released plugin): the focus
  // chip takes the windows' material. Raised = an accent pebble standing on
  // the pill; Recessed = a socket pressed into it; Depth off = flat tint.
  property var depthSettings: ({})
  readonly property bool lightTheme: Commons.Color.bar.background.hslLightness > 0.55
  readonly property bool depthOn: depthSettings.enabled === true
  readonly property string material: !depthOn ? "flat" : depthSettings.style === "raised" ? "raised" : "recessed"
  readonly property var depthProfile: {
    var style = depthSettings.styles ? depthSettings.styles[material === "raised" ? "raised" : "recessed"] : null
    return style ? (style[lightTheme ? "light" : "dark"] || {}) : {}
  }
  function depthValue(key, fallback) { var n = Number(depthProfile[key]); return isNaN(n) ? fallback : Math.max(0, Math.min(1, n)) }
  readonly property real height01: depthValue("win_depth", 0.6)
  readonly property real sheen01: depthValue("win_lip", 0.6)
  readonly property color accent: Commons.Color.accent
  readonly property real recessNight: {
    var c = Commons.Color.bar.background
    var brightness = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    var t = lightTheme ? 0 : Math.max(0, Math.min(1, (0.12 - brightness) / 0.085))
    return t * t * (3 - 2 * t)
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/inferna/recess.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.depthSettings = JSON.parse(text()) } catch (e) { root.depthSettings = {} } }
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight + trackPad * 2

  Rectangle {
    id: track
    visible: root.tideRail
    width: Style.space(28)
    height: root.height
    x: (root.barSize - width) / 2
    radius: width / 2
    color: root.lightTheme ? Qt.rgba(0, 0, 0, 0.07) : Qt.rgba(0, 0, 0, 0.3)
    // Shade cast down from the rim, and a faint lit lip at the bottom.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, root.lightTheme ? 0.12 : 0.35) }
        GradientStop { position: 0.12; color: "transparent" }
        GradientStop { position: 0.92; color: "transparent" }
        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, root.lightTheme ? 0.35 : 0.06) }
      }
    }
  }

  // ---------------------------------------------------------- focus chip
  // One chip travels between numbers on a spring (bounces once, then
  // settles). The spring is integrated here, per real frame, so its velocity
  // is known: the chip stretches with its *speed* (round at rest, at launch
  // and at the top of the bounce), leans slightly into its direction of
  // travel, and keeps its momentum when you switch again mid-flight.
  Item {
    id: chip
    // Raised: a 22px pebble (a true circle at rest, a capsule while it
    // stretches). Recessed/flat: the original 23×22 rounded socket.
    readonly property bool round: root.material === "raised" || root.tideRail
    readonly property real baseW: root.tideRail ? Style.space(22) : round ? 22 : 23
    readonly property real baseH: root.tideRail ? Style.space(40) : 22
    readonly property Item target: root.focusedIndex >= 0 && repeater.count > root.focusedIndex ? repeater.itemAt(root.focusedIndex) : null
    readonly property real targetC: target ? (root.vertical ? grid.y + target.y + target.height / 2 : grid.x + target.x + target.width / 2) : center
    property real center: 0
    property real velocity: 0
    property bool ready: false
    property real pop: 1

    // Damping ratio ~0.58: one ~10% overshoot, arrives in ~170ms, at rest by
    // ~0.5s. Same bounce the user tuned, without Qt SpringAnimation's fixed
    // 16ms steps (which double-step a frame now and then at 60Hz).
    readonly property real stiffness: 290
    readonly property real damping: 19.6
    function step(dt) {
      var n = Math.max(1, Math.ceil(dt / 0.004)), h = dt / n
      var x = center, v = velocity, goal = targetC
      for (var i = 0; i < n; i++) {
        v += (stiffness * (goal - x) - damping * v) * h
        x += v * h
      }
      if (Math.abs(goal - x) < 0.05 && Math.abs(v) < 1) { x = goal; v = 0 }
      velocity = v
      center = x
    }
    FrameAnimation {
      running: chip.ready && (chip.center !== chip.targetC || chip.velocity !== 0)
      onTriggered: chip.step(Math.min(frameTime > 0 ? frameTime : 1 / 60, 1 / 30))
    }

    onTargetCChanged: {
      if (!ready) { center = targetC; return }
      // A small anticipation dip on a fresh move only; rapid repeat switches
      // just redirect the moving chip without restarting it.
      if (target && Math.abs(velocity) < 40) launch.restart()
    }
    Component.onCompleted: { center = targetC; Qt.callLater(function() { chip.center = chip.targetC; chip.ready = true }) }

    SequentialAnimation {
      id: launch
      NumberAnimation { target: chip; property: "pop"; to: 0.95; duration: 60; easing.type: Easing.OutQuad }
      NumberAnimation { target: chip; property: "pop"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }

    // Deformation follows speed: up to +10px along the travel (a 1-step move
    // peaks near +6px) and at most 5% thinner across it.
    readonly property real speed: Math.abs(velocity)
    readonly property real stretch: Math.min(10, speed * 0.024)
    readonly property real thin: Math.min(baseH * 0.05, speed * 0.002)
    readonly property real w: (root.vertical ? baseW - thin : baseW + stretch) * pop
    readonly property real h: (root.vertical ? baseH + stretch : baseH - thin) * pop
    readonly property real lead: (velocity >= 0 ? 1 : -1) * stretch * 0.3
    // Rest on whole device pixels so the edges stay crisp at fractional scale.
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    function snap(v) { return Math.round(v * dpr) / dpr }
    width: snap(w)
    height: snap(h)
    x: snap(root.vertical ? (root.barSize - w) / 2 : center - w / 2 + lead)
    y: snap(root.vertical ? center - h / 2 + lead : (root.barSize - h) / 2)
    opacity: target ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    property real radius: round ? height / 2 : Math.min(7, height / 2)
    Behavior on radius { SpringAnimation { spring: 3; damping: 0.3; epsilon: 0.05 } }

    // Raised: a small drop shadow, cut away under the translucent pebble.
    OutsideShadow {
      visible: root.material === "raised"
      anchors.fill: parent
      radius: chip.radius
      offsetY: 1 + 1.5 * root.height01
      blur: 3 + 4 * root.height01
      color: Qt.rgba(0, 0, 0, root.lightTheme ? 0.1 + 0.15 * root.height01 : 0.3 + 0.3 * root.height01)
    }

    Rectangle {
      id: body
      anchors.fill: parent
      radius: chip.radius
      antialiasing: true
      color: root.tideRail ? root.accent
        : root.material === "raised"
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.lightTheme ? 0.78 : 0.62)
        : root.material === "recessed"
          ? Qt.rgba(root.accent.r * 0.45, root.accent.g * 0.45, root.accent.b * 0.45, root.lightTheme ? 0.3 : 0.45)
          : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.40)
      Behavior on color { ColorAnimation { duration: 240; easing.type: Easing.OutCubic } }

      // Raised: convex sheen, lit on top and shaded at the bottom.
      Rectangle {
        visible: root.material === "raised"
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root.sheen01 * (root.lightTheme ? 0.4 : 0.26)) }
          GradientStop { position: 0.55; color: "transparent" }
          GradientStop { position: 1; color: Qt.rgba(0, 0, 0, root.height01 * (root.lightTheme ? 0.1 : 0.22)) }
        }
      }
      // Recessed: shade cast down from the top edge inside the socket.
      Rectangle {
        visible: root.material === "recessed"
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(0, 0, 0, root.height01 * (root.lightTheme ? 0.3 : 0.6)) }
          GradientStop { position: 0.45 - 0.12 * root.recessNight; color: "transparent" }
        }
      }
    }

    Text {
      visible: root.tideRail
      anchors.centerIn: parent
      text: Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.id === 10 ? "0" : String(Hyprland.focusedWorkspace.id)) : ""
      color: root.lightTheme ? "white" : Commons.Color.background
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.space(11)
      font.weight: Font.Bold
      renderType: Text.NativeRendering
    }

    // One continuous rim, top to bottom: a pebble catches the light on top and
    // darkens into its lower edge; a socket carries the cut on top and a faint
    // lit lip at the bottom.
    RimRing {
      visible: root.material !== "flat"
      anchors.fill: parent
      radius: chip.radius
      readonly property real topA: root.material === "raised" ? root.sheen01 * (root.lightTheme ? 0.95 : 0.5) : root.height01 * (root.lightTheme ? 0.3 : 0.7)
      readonly property real bottomA: root.material === "raised"
        ? (root.lightTheme ? 0.12 + 0.12 * root.height01 : 0.3 + 0.3 * root.height01)
        : root.sheen01 * (root.lightTheme ? 0.85 : 0.16 + 0.1 * root.recessNight)
      c0: root.material === "raised" ? Qt.rgba(1, 1, 1, topA) : Qt.rgba(0, 0, 0, topA)
      c1: root.material === "raised" ? Qt.rgba(1, 1, 1, topA * 0.45) : Qt.rgba(0, 0, 0, topA * 0.4)
      c2: root.material === "raised" ? Qt.rgba(1, 1, 1, topA * 0.12) : "transparent"
      c3: root.material === "raised" ? Qt.rgba(0, 0, 0, bottomA * 0.45) : Qt.rgba(1, 1, 1, bottomA * 0.35)
      c4: root.material === "raised" ? Qt.rgba(0, 0, 0, bottomA) : Qt.rgba(1, 1, 1, bottomA)
    }
  }

  // A 1px rounded ring whose colour follows a five-stop vertical gradient.
  component RimRing: Item {
    id: rim
    property real radius: 0
    property color c0: "transparent"
    property color c1: "transparent"
    property color c2: "transparent"
    property color c3: "transparent"
    property color c4: "transparent"
    Rectangle {
      id: rimFill
      anchors.fill: parent
      visible: false
      gradient: Gradient {
        GradientStop { position: 0; color: rim.c0 }
        GradientStop { position: 0.3; color: rim.c1 }
        GradientStop { position: 0.55; color: rim.c2 }
        GradientStop { position: 0.8; color: rim.c3 }
        GradientStop { position: 1; color: rim.c4 }
      }
    }
    Rectangle {
      id: rimShape
      anchors.fill: parent
      visible: false
      radius: rim.radius
      color: "transparent"
      antialiasing: true
      border.width: 1
      border.color: "black"
    }
    OpacityMask { anchors.fill: parent; source: rimFill; maskSource: rimShape }
  }

  // A soft drop shadow cut away wherever the shape itself is.
  component OutsideShadow: Item {
    id: outside
    property real radius: 0
    property real offsetY: 2
    property real blur: 6
    property color color: Qt.rgba(0, 0, 0, 0.3)
    readonly property real pad: Math.ceil(blur + Math.abs(offsetY) + 2)
    Item {
      id: shadowSource
      x: -outside.pad; y: -outside.pad
      width: outside.width + outside.pad * 2; height: outside.height + outside.pad * 2
      visible: false
      RectangularShadow {
        x: outside.pad; y: outside.pad
        width: outside.width; height: outside.height
        radius: outside.radius
        offset.y: outside.offsetY
        blur: outside.blur
        spread: -1
        color: outside.color
      }
    }
    Item {
      id: shadowCut
      anchors.fill: shadowSource
      visible: false
      Rectangle {
        x: outside.pad; y: outside.pad
        width: outside.width; height: outside.height
        radius: outside.radius
        antialiasing: true
        color: "black"
      }
    }
    OpacityMask { anchors.fill: shadowSource; source: shadowSource; maskSource: shadowCut; invert: true }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    anchors.topMargin: root.trackPad
    anchors.bottomMargin: root.trackPad
    columns: root.vertical ? 1 : root.ids.length
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical && !root.tideRail ? Style.space(2) : 0

    Repeater {
      id: repeater
      model: root.ids

      Item {
        id: workspaceDelegate
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        implicitWidth: root.vertical ? root.barSize : Style.space(23)
        implicitHeight: root.tideRail ? (focused ? Style.space(46) : Style.space(14)) : root.barSize
        Behavior on implicitHeight { enabled: root.tideRail; NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

        Rectangle {
          visible: root.tideRail
          anchors.centerIn: parent
          width: Style.space(7); height: width; radius: width / 2
          color: Qt.rgba(root.bar ? root.bar.foreground.r : 1, root.bar ? root.bar.foreground.g : 1, root.bar ? root.bar.foreground.b : 1, workspaceDelegate.occupied ? 0.7 : 0.28)
          opacity: workspaceDelegate.focused ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        WidgetButton {
          id: workspaceButton
          anchors.fill: parent
          bar: root.bar
          text: workspaceDelegate.modelData === 10 ? "0" : String(workspaceDelegate.modelData)
          // WidgetButton centers a whole font line box and rounds its anchor
          // position. Digits have no descenders, and unequal side bearings
          // (especially 1 and 4), so that leaves their ink high and off-center.
          // Keep its existing hit target/tooltip/click registration, and draw
          // the numeral ourselves around the same center the chip targets.
          labelVisible: false
          opacity: workspaceDelegate.occupied || workspaceDelegate.focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: parent.width
          fixedHeight: parent.height
          onPressed: function() { root.focusWorkspace(workspaceDelegate.modelData) }

          TextMetrics {
            id: digitMetrics
            font: numeral.font
            text: numeral.text
          }
          FontMetrics {
            id: digitFontMetrics
            font: numeral.font
          }
          Text {
            id: numeral
            readonly property rect ink: digitMetrics.tightBoundingRect
            text: workspaceButton.text
            textFormat: Text.PlainText
            font.family: workspaceButton.fontFamily
            font.pixelSize: workspaceButton.fontSize
            renderType: Text.NativeRendering
            visible: !root.tideRail
            // Center each glyph's ink horizontally; vertically, use a shared
            // cap-height baseline so curved digits keep their natural tiny
            // overshoot rather than jumping relative to their neighbors.
            // No center anchors: those round narrow glyphs away from the chip.
            x: (parent.width - ink.width) / 2 - ink.x
            y: (parent.height + digitFontMetrics.capitalHeight) / 2 - baselineOffset
            color: workspaceButton.active && workspaceButton.useActiveColor
              ? workspaceButton.activeColor : workspaceButton.foreground
            Behavior on color {
              enabled: !root.bar || root.bar.foregroundAnimationEnabled
              ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
          }
        }
      }
    }
  }
}
