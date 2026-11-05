import "../denon.bar/panels" as Motion
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Depth (direction R-B · Paired swatches): windows either recessed into the
// screen or raised off it like pebbles. Three looks per style, each shown as a
// light and a dark half, scaled by one Intensity groove; a live preview draws
// the effect with the same maths Hyprland uses (recessed_windows.lua). Details
// opens the four raw sliders. Each style keeps light and dark profiles;
// settings live in ~/.config/inferna/recess.json (control.py).
Panel {
  id: root
  moduleName: "denon.recess"
  ipcTarget: "denon.recess"
  manageIpc: false
  implicitWidth: icon.implicitWidth
  implicitHeight: icon.implicitHeight
  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property string mono: "Adwaita Mono"
  readonly property string helper: Quickshell.env("HOME") + "/.local/share/inferna-recess/control.py"
  readonly property string wallpaper: "file://" + Quickshell.env("HOME") + "/.local/state/inferna/current/background"
  property var values: ({enabled: true, style: "recessed", styles: {}})
  property var allLooks: ({})        // style -> look -> profile -> base sliders, from control.py
  readonly property string style: values.style === "raised" ? "raised" : "recessed"
  readonly property bool raised: style === "raised"
  readonly property var looks: allLooks[style] || ({})
  property string theme: "dark"      // active theme brightness, from control.py
  property string profile: "dark"    // profile being edited
  readonly property var prof: values.styles && values.styles[style] && values.styles[style][profile] ? values.styles[style][profile] : ({})
  property var draft: ({})           // values being dragged, previewed before release
  property var pending: ({})
  property bool loaded: false
  property bool details: false
  property int openCount: 0
  property int selectedRow: 2        // 0 switch · 1 style · 2 looks · 3 intensity · 4 profile · 5.. details
  property string message: ""

  readonly property var lookList: raised
    ? [{id: "soft", label: "Soft"}, {id: "pebble", label: "Pebble"}, {id: "lifted", label: "Lifted"}]
    : [{id: "subtle", label: "Subtle"}, {id: "carved", label: "Carved"}, {id: "deep", label: "Deep"}]
  readonly property var styleList: [{id: "recessed", label: "Recessed"}, {id: "raised", label: "Raised"}]
  readonly property var controls: [
    {key: "win_depth", label: raised ? "Height" : "Depth", min: 0, max: 1, step: 0.05, unit: "%"},
    {key: "win_soft", label: raised ? "Shadow softness" : "Softness", min: 2, max: 30, step: 1, unit: "px"},
    {key: "win_light", label: "Light from above", min: 0, max: 1, step: 0.05, unit: "%"},
    {key: "win_lip", label: raised ? "Top sheen" : "Lower highlight", min: 0, max: 1, step: 0.05, unit: "%"}
  ]
  readonly property int lastRow: details ? 4 + controls.length : 4
  readonly property bool busy: writeProc.running || readProc.running
  readonly property bool custom: prof.look === "custom"
  readonly property int intensity: draft.intensity !== undefined ? draft.intensity : Number(prof.intensity === undefined ? 50 : prof.intensity)
  // What the preview shows: saved values, or the drag in progress.
  readonly property var effective: {
    if (draft.intensity !== undefined && !custom) return scaled(prof.look, profile, draft.intensity)
    return Object.assign({}, prof, draft)
  }

  function alphaOf(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function fmt(spec, v) { return spec.unit === "px" ? Math.round(v || 0) + " px" : Math.round((v || 0) * 100) + "%" }
  // Mirrors control.py scaled(): 50 = the look as designed.
  function scaled(look, which, value) {
    var base = looks[look] ? looks[look][which] : null
    if (!base) return prof
    var k = value / 50
    return {win_depth: Math.min(1, base.win_depth * k), win_soft: Math.max(2, Math.min(30, Math.round(base.win_soft * (0.5 + 0.5 * k)))),
            win_light: base.win_light, win_lip: Math.min(1, base.win_lip * k)}
  }

  function refresh() { if (!busy && Object.keys(pending).length === 0) readProc.running = true }
  function receive(text, saved) {
    try {
      const result = JSON.parse(text)
      if (result.looks) allLooks = result.looks
      values = result.values
      if (result.theme && (!loaded || result.theme !== theme)) { theme = result.theme; profile = result.theme }
      loaded = true
      message = result.ok ? "" : result.error
    } catch (e) { message = "Could not read Recess settings." }
  }
  // Commands queue per profile so a quick sequence never lands on the wrong one.
  function send(args) {
    if (!loaded) return
    const p = Object.assign({}, pending); p[JSON.stringify(args.concat(["--profile", profile, "--style", style]))] = true; pending = p
    drain()
  }
  function drain() {
    if (busy || Object.keys(pending).length === 0) return
    const id = Object.keys(pending)[0]
    const p = Object.assign({}, pending); delete p[id]; pending = p
    writeProc.command = ["python3", helper].concat(JSON.parse(id))
    writeProc.running = true
  }
  function commit(key, value) {
    const d = Object.assign({}, draft); delete d[key]; draft = d
    const v = JSON.parse(JSON.stringify(values))
    const target = v.styles[style][profile]
    if (key === "enabled") v.enabled = value
    else if (key === "style") v.style = value
    else if (key === "intensity") { target.intensity = value; Object.assign(target, scaled(prof.look, profile, value)) }
    else { target[key] = value; target.look = "custom" }
    values = v
    send(["set", key, String(value)])
  }
  function pickLook(id) {
    const v = JSON.parse(JSON.stringify(values))
    v.styles[style][profile].look = id
    Object.assign(v.styles[style][profile], scaled(id, profile, intensity))
    values = v
    send(["preset", id])
  }
  function lookIndex() {
    for (var i = 0; i < lookList.length; i++) if (lookList[i].id === prof.look) return i
    return 1
  }

  function setStyle(id) { if (id !== style) { draft = {}; commit("style", id) } }
  function adjust(dx) {
    if (selectedRow === 1) setStyle(dx > 0 ? "raised" : "recessed")
    else if (selectedRow === 2) pickLook(lookList[Math.max(0, Math.min(2, lookIndex() + dx))].id)
    else if (selectedRow === 3 && !custom) commit("intensity", Math.max(0, Math.min(100, intensity + dx * 5)))
    else if (selectedRow === 4) profile = dx > 0 ? "dark" : "light"
    else if (selectedRow >= 5) {
      const c = controls[selectedRow - 5]
      commit(c.key, Math.round(Math.max(c.min, Math.min(c.max, Number(prof[c.key]) + dx * c.step)) * 1000) / 1000)
    }
  }
  function activate() {
    if (selectedRow === 0) commit("enabled", !values.enabled)
    else if (selectedRow === 1) setStyle(raised ? "recessed" : "raised")
    else if (selectedRow === 4) profile = profile === "light" ? "dark" : "light"
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { openCount++; profile = theme; draft = {}; refresh() }

  IpcHandler {
    target: "denon.recess"
    function open(): void { root.open(); root.refresh() }
    function close(): void { root.close() }
    function state(): string { return JSON.stringify({values: root.values, theme: root.theme, profile: root.profile, details: root.details, loaded: root.loaded, message: root.message, busy: root.busy}) }
    function setProfile(name: string): void { root.profile = name === "light" ? "light" : "dark" }
    function set(key: string, value: string): void { root.commit(key, key === "enabled" ? value === "true" : Number(value)) }
    function look(id: string): void { root.pickLook(id) }
    function setStyle(id: string): void { root.setStyle(id === "raised" ? "raised" : "recessed") }
    function showDetails(on: bool): void { root.details = on }
    function preview(value: int): void { root.draft = {intensity: value} }
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
    text: "▣"
    tooltipText: !root.values.enabled ? "Depth · off" : root.raised ? "Depth · windows raised off the screen" : "Depth · windows pressed into the screen"
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
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyboard
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy) root.selectedRow = Math.max(0, Math.min(root.lastRow, root.selectedRow + dy))
        else root.adjust(dx)
      }
      onActivateRequested: root.activate()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(16)

        // ---------- Header: big title · caption · switch ----------
        Item {
          width: parent.width
          height: Math.max(titleCol.implicitHeight, toggle.height)
          Column {
            id: titleCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)
            Text {
              text: "Depth"; color: root.fg; font.family: root.family
              font.pixelSize: Style.font.title + 3; font.weight: Font.Bold
            }
            Text {
              text: !root.values.enabled ? "Off · windows use the theme's frames"
                : root.raised ? "Windows lifted off the screen" : "Windows pressed into the screen"
              color: root.alphaOf(root.fg, 0.55); font.family: root.family; font.pixelSize: Style.font.caption + 1
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
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              enabled: root.loaded
              onClicked: root.commit("enabled", !root.values.enabled)
              onEntered: root.selectedRow = 0
            }
          }
        }

        // ---------- Style: recessed or raised ----------
        Motion.GlassTrack {
          width: parent.width; foreground: root.fg
          opacity: root.values.enabled ? 1 : 0.5
          Row {
            width: parent.width; spacing: Style.space(2)
            Repeater {
              model: root.styleList
              Button {
                required property var modelData
                width: (parent.width - Style.space(2)) / 2
                text: modelData.label; foreground: root.fg; fontFamily: root.family; bordered: false
                active: root.style === modelData.id
                hasCursor: root.selectedRow === 1 && root.style === modelData.id
                onClicked: root.setStyle(modelData.id)
                onHovered: function(hovered) { if (hovered) root.selectedRow = 1 }
              }
            }
          }
        }

        // ---------- Live preview: your wallpaper, your theme, the real maths ----------
        ClippingRectangle {
          width: parent.width
          height: Style.space(132)
          radius: Style.space(12)
          color: root.alphaOf(root.fg, 0.06)
          Image {
            anchors.fill: parent
            source: root.wallpaper + "?" + root.openCount
            sourceSize.width: 480
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
          Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, root.profile === "dark" ? 0.22 : 0.05) }
          MiniWindow {
            anchors.centerIn: parent
            width: parent.width * 0.62; height: parent.height * 0.66
            radius: Style.space(12)
            look: root.values.enabled ? root.effective : ({win_depth: 0, win_soft: 2, win_light: 0, win_lip: 0})
            lightMode: root.profile === "light"
            base: root.profile === root.theme ? Commons.Color.background : (root.profile === "light" ? "#F4F0E8" : "#1E1A1B")
            ink: root.profile === root.theme ? Commons.Color.foreground : (root.profile === "light" ? "#2B241A" : "#E9DFC8")
            showLines: true
            raised: root.raised
          }
          Text {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            anchors.margins: Style.space(9)
            text: "LIVE · " + (root.profile === root.theme ? "your theme" : root.profile + " themes")
            color: Qt.rgba(1, 1, 1, 0.7); font.family: root.family; font.pixelSize: Style.font.caption - 1; font.letterSpacing: 0.6
            style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.35)
          }
        }

        // ---------- Looks: light half · dark half ----------
        Row {
          width: parent.width
          spacing: Style.space(10)
          Repeater {
            model: root.lookList
            Column {
              id: swatch
              required property var modelData
              required property int index
              readonly property bool selected: root.prof.look === modelData.id
              readonly property bool hovered: swatchMouse.containsMouse
              width: (parent.width - Style.space(20)) / 3
              spacing: Style.space(7)
              Rectangle {
                width: parent.width; height: Style.space(70)
                radius: Style.space(12)
                color: "transparent"
                border.width: swatch.selected ? 2 : 1
                border.color: swatch.selected ? root.accent : root.alphaOf(root.fg, swatch.hovered || (root.selectedRow === 2 && swatch.selected) ? 0.35 : 0.1)
                ClippingRectangle {
                  anchors.fill: parent; anchors.margins: parent.border.width
                  radius: parent.radius - parent.border.width
                  color: "transparent"
                  Row {
                    anchors.fill: parent
                    Repeater {
                      model: ["light", "dark"]
                      Rectangle {
                        required property string modelData
                        width: parent.width / 2; height: parent.height
                        color: modelData === "light" ? "#E8E1D3" : "#2A1718"
                        MiniWindow {
                          anchors.centerIn: parent
                          width: parent.width * 0.62; height: parent.height * 0.66
                          radius: Style.space(6)
                          scale: 1
                          softScale: 0.5
                          look: root.looks[swatch.modelData.id] ? root.looks[swatch.modelData.id][parent.modelData] : ({})
                          lightMode: parent.modelData === "light"
                          base: parent.modelData === "light" ? "#F6F2EA" : "#1B1112"
                          raised: root.raised
                        }
                      }
                    }
                  }
                }
                MouseArea {
                  id: swatchMouse
                  anchors.fill: parent
                  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  enabled: root.loaded
                  onClicked: root.pickLook(swatch.modelData.id)
                  onEntered: root.selectedRow = 2
                }
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: swatch.modelData.label
                color: swatch.selected ? root.fg : root.alphaOf(root.fg, 0.62)
                font.family: root.family; font.pixelSize: Style.font.caption + 1
                font.weight: swatch.selected ? Font.Bold : Font.Normal
              }
            }
          }
        }

        // ---------- Intensity: the carved groove ----------
        Rectangle {
          width: parent.width
          height: intensityCol.implicitHeight + Style.space(28)
          radius: Style.space(14)
          color: root.alphaOf(root.fg, 0.05)
          border.width: root.selectedRow === 3 ? 1 : 0
          border.color: root.alphaOf(root.fg, 0.25)
          Column {
            id: intensityCol
            x: Style.space(14); y: Style.space(14)
            width: parent.width - Style.space(28)
            spacing: Style.space(12)
            Item {
              width: parent.width
              height: Math.max(intensityLabel.implicitHeight, intensityValue.implicitHeight)
              Column {
                id: intensityLabel
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text { text: "Intensity"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body + 1; font.weight: Font.DemiBold }
                Text {
                  text: root.custom ? "Custom · pick a look to use this"
                    : root.raised ? "Height, shadow and sheen together" : "Depth, softness and lip together"
                  color: root.alphaOf(root.fg, 0.5); font.family: root.family; font.pixelSize: Style.font.caption
                }
              }
              Text {
                id: intensityValue
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: root.custom ? "—" : String(root.intensity)
                color: root.custom ? root.alphaOf(root.fg, 0.4) : root.accent
                font.family: root.mono; font.pixelSize: Style.font.title + 9; font.weight: Font.Bold
              }
            }
            Groove {
              width: parent.width
              value: root.intensity
              enabled: root.loaded && !root.custom
              opacity: root.custom ? 0.4 : 1
            }
          }
        }

        // ---------- Details: the four raw sliders ----------
        Column {
          visible: root.details
          width: parent.width
          spacing: Style.space(12)
          opacity: root.values.enabled ? 1 : 0.45
          Repeater {
            model: root.controls
            Slider {
              required property var modelData
              required property int index
              width: content.width
              spec: modelData
              row: index + 5
            }
          }
        }

        // ---------- Footer: profile · details ----------
        Item {
          width: parent.width
          height: Style.space(20)
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(9); height: width; radius: width / 2
              color: root.profile === "light" ? "#F4F0E8" : "#1B1112"
              border.width: 1; border.color: root.alphaOf(root.fg, 0.45)
            }
            Text {
              text: "Editing " + root.profile + " themes" + (root.profile === root.theme ? " · now active" : " · tap to switch")
              color: root.alphaOf(root.fg, root.selectedRow === 4 || profileMouse.containsMouse ? 0.95 : 0.7)
              font.family: root.family; font.pixelSize: Style.font.caption + 1
              MouseArea {
                id: profileMouse
                anchors.fill: parent; anchors.margins: -Style.space(4)
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.profile = root.profile === "light" ? "dark" : "light"
                onEntered: root.selectedRow = 4
              }
            }
          }
          Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: root.details ? "Less ‹" : "Details ›"
            color: root.alphaOf(root.fg, detailsMouse.containsMouse ? 0.95 : 0.7)
            font.family: root.family; font.pixelSize: Style.font.caption + 1; font.weight: Font.DemiBold
            MouseArea {
              id: detailsMouse
              anchors.fill: parent; anchors.margins: -Style.space(4)
              hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: root.details = !root.details
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.message
          color: Commons.Color.urgent; font.family: root.family; font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  // A window drawn the way recessed_windows.lua draws it.
  // Recessed: an inner shade fading in from every edge (strongest at the top,
  // scaled by "light from above") and a border from a dark top cut to a lit
  // lower lip. Raised (pebble): a dark outline, a soft lit rim rolling off the
  // edge all the way around (brightest on top; "light from above" sets how far
  // it wraps), and a soft drop shadow tucked under the pane.
  component MiniWindow: Item {
    id: mw
    property var look: ({})
    property bool lightMode: false
    property bool raised: false
    property color base: "#1B1112"
    property color ink: "#E9DFC8"
    property real radius: 10
    property real softScale: 1
    property bool showLines: false
    readonly property real depth: Number(look.win_depth || 0)
    readonly property real bias: Number(look.win_light || 0)
    readonly property real night: {
      var brightness = 0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b
      var t = lightMode ? 0 : Math.max(0, Math.min(1, (0.12 - brightness) / 0.085))
      return t * t * (3 - 2 * t)
    }
    // Mirror the generated window module: tighten the shade on near-black
    // faces, with a clearer theme-tinted lower lip (never an upper glow).
    readonly property real soft: Math.max(1, (raised ? Number(look.win_soft || 2)
      : Math.max(2, Math.round(Number(look.win_soft || 2) * (1 - 0.35 * night)))) * softScale)
    // recessed
    readonly property real a: depth * (lightMode ? 0.45 : 0.85 + 0.1 * night)
    readonly property real edgeTop: a
    readonly property real mid: a * (1 - bias * 0.5)
    readonly property real edgeBottom: a * (1 - bias)
    readonly property real lip: Number(look.win_lip || 0) * (lightMode ? 0.85 : 0.2 + 0.16 * night)
    readonly property color lipTint: Qt.rgba(1 + (ink.r - 1) * night, 1 + (ink.g - 1) * night, 1 + (ink.b - 1) * night, lip)
    // raised: same coefficients as the Lua module
    readonly property real outline: lightMode ? 0.05 + 0.14 * depth : 0.12 + 0.32 * depth
    readonly property real sheen: Number(look.win_lip || 0) * (lightMode ? 1.0 : 0.85)
    readonly property real bevelShade: (lightMode ? 0.04 + 0.12 * depth : 0.1 + 0.3 * depth) * (0.6 + 0.4 * bias)
    readonly property real lift: depth * (lightMode ? 0.36 : 0.8)
    readonly property real bevel: 2 + Math.round(soft * 0.3)
    // Rim strength top→bottom, mirroring the Lua stops (last may be shade).
    readonly property var rim: {
      var topOnly = [1, 0.29, 0.07, 0, 0, 0], wrapped = [1, 0.8, 0.7, 0.66, 0.62, 0.58], out = []
      for (var i = 0; i < 6; i++) out.push(sheen * (topOnly[i] * bias + wrapped[i] * (1 - bias)))
      out.push(sheen * 0.3 * (1 - bias) - bevelShade * bias)
      return out
    }
    function rimColor(v) { return v >= 0 ? Qt.rgba(1, 1, 1, v) : Qt.rgba(0, 0, 0, -v) }

    RectangularShadow {
      visible: mw.raised && mw.lift > 0
      anchors.fill: parent
      radius: mw.radius
      spread: -Math.max(1, mw.width * 0.01)
      offset.y: mw.soft * (0.2 + 0.35 * mw.bias)
      blur: mw.soft * 1.6
      color: Qt.rgba(0, 0, 0, Math.min(1, mw.lift))
    }
    // Gradient border: the frame shows through a 1px gap around the face.
    Rectangle {
      visible: mw.raised || mw.night === 0
      anchors.fill: parent
      radius: mw.radius
      gradient: Gradient {
        GradientStop { position: 0; color: mw.raised ? Qt.rgba(0, 0, 0, mw.outline * 0.95) : Qt.rgba(0, 0, 0, mw.edgeTop * 0.85) }
        GradientStop { position: 0.5; color: mw.raised ? Qt.rgba(0, 0, 0, mw.outline * 1.1) : Qt.rgba(0, 0, 0, mw.edgeTop * 0.15) }
        GradientStop { position: 1; color: mw.raised ? Qt.rgba(0, 0, 0, Math.min(1, mw.outline * 1.6)) : Qt.rgba(1, 1, 1, mw.lip) }
      }
    }
    Rectangle {
      visible: !mw.raised && mw.night > 0
      anchors.fill: parent
      radius: mw.radius
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, mw.edgeTop * 0.85) }
        GradientStop { position: 0.25; color: Qt.rgba(0, 0, 0, mw.edgeTop * (0.5 + 0.15 * mw.night)) }
        GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, mw.edgeTop * 0.15) }
        GradientStop { position: 0.75; color: root.alphaOf(mw.lipTint, mw.lip * (0.5 + 0.1 * mw.night)) }
        GradientStop { position: 1; color: mw.lipTint }
      }
    }
    ClippingRectangle {
      anchors.fill: parent; anchors.margins: 1
      radius: Math.max(0, mw.radius - 1)
      color: mw.base
      Column {
        visible: mw.showLines
        x: mw.width * 0.1; y: mw.height * 0.26
        spacing: Style.space(6)
        Rectangle { width: mw.width * 0.28; height: Style.space(6); radius: 3; color: root.alphaOf(mw.ink, 0.3) }
        Rectangle { width: mw.width * 0.62; height: Style.space(6); radius: 3; color: root.alphaOf(mw.ink, 0.16) }
        Rectangle { width: mw.width * 0.5; height: Style.space(6); radius: 3; color: root.alphaOf(mw.ink, 0.16) }
      }
      // Raised rim: rolls off the edge all the way around with the same cubic
      // falloff as Hyprland's glow (render_power 3). Sides are 1px columns, each
      // carrying the top→bottom rim profile at its distance's strength.
      Item {
        visible: mw.raised
        anchors.fill: parent
        Rectangle {
          width: parent.width; height: mw.bevel
          gradient: Gradient {
            GradientStop { position: 0; color: mw.rimColor(mw.rim[0]) }
            GradientStop { position: 0.25; color: mw.rimColor(mw.rim[0] * 0.42) }
            GradientStop { position: 0.5; color: mw.rimColor(mw.rim[0] * 0.125) }
            GradientStop { position: 1; color: "transparent" }
          }
        }
        Rectangle {
          y: parent.height - height; width: parent.width; height: mw.bevel
          gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: mw.rimColor(mw.rim[6] * 0.125) }
            GradientStop { position: 0.75; color: mw.rimColor(mw.rim[6] * 0.42) }
            GradientStop { position: 1; color: mw.rimColor(mw.rim[6]) }
          }
        }
        Repeater {
          model: Math.max(1, Math.round(mw.bevel)) * 2
          Rectangle {
            required property int index
            readonly property int step: index % Math.max(1, Math.round(mw.bevel))
            x: index < Math.round(mw.bevel) ? step : parent.width - 1 - step
            width: 1; height: parent.height
            opacity: Math.pow(1 - step / Math.max(1, mw.bevel), 3)
            gradient: Gradient {
              GradientStop { position: 0; color: mw.rimColor(mw.rim[0]) }
              GradientStop { position: 1 / 6; color: mw.rimColor(mw.rim[1]) }
              GradientStop { position: 2 / 6; color: mw.rimColor(mw.rim[2]) }
              GradientStop { position: 3 / 6; color: mw.rimColor(mw.rim[3]) }
              GradientStop { position: 4 / 6; color: mw.rimColor(mw.rim[4]) }
              GradientStop { position: 5 / 6; color: mw.rimColor(mw.rim[5]) }
              GradientStop { position: 1; color: mw.rimColor(mw.rim[6]) }
            }
          }
        }
      }
      // Recessed: four edge fades (quadratic-ish, like Hyprland's glow).
      Item {
        visible: !mw.raised
        anchors.fill: parent
        Rectangle {
          width: parent.width; height: mw.soft
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, mw.edgeTop) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, mw.edgeTop * 0.4) }
            GradientStop { position: 1; color: "transparent" }
          }
        }
        Rectangle {
          y: parent.height - height; width: parent.width; height: mw.soft
          gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, mw.edgeBottom * 0.4) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, mw.edgeBottom) }
          }
        }
        Rectangle {
          width: mw.soft; height: parent.height
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, mw.mid) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, mw.mid * 0.4) }
            GradientStop { position: 1; color: "transparent" }
          }
        }
        Rectangle {
          x: parent.width - width; width: mw.soft; height: parent.height
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, mw.mid * 0.4) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, mw.mid) }
          }
        }
      }
    }
  }

  // Intensity groove: a channel carved into the card that gets deeper as the
  // value rises, an accent fill, a raised pebble thumb, and a notch at 50 (the
  // look as designed). Previews while dragging; applies on release.
  component Groove: Column {
    id: g
    property real value: 50
    property bool dragging: false
    property real live: value
    readonly property real progress: Math.max(0, Math.min(1, live / 100))
    spacing: Style.space(6)
    onValueChanged: if (!dragging) live = value

    Item {
      width: parent.width
      height: Style.space(26)
      Rectangle {
        id: channel
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Style.space(14); radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.22 + 0.16 * g.progress)
        Behavior on color { ColorAnimation { duration: 120 } }
        // The cut: a top shadow that deepens with the value…
        Rectangle {
          anchors.fill: parent; radius: parent.radius
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.25 + 0.5 * g.progress) }
            GradientStop { position: 0.55; color: "transparent" }
          }
        }
        // …and a faint lit lip along the bottom edge.
        Rectangle {
          anchors.bottom: parent.bottom
          x: parent.radius; width: parent.width - parent.radius * 2; height: 1
          color: root.alphaOf(root.fg, 0.1)
        }
        // Fill: sunk inside the channel.
        Rectangle {
          x: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(height, (parent.width - Style.space(8)) * g.progress)
          height: Style.space(6); radius: height / 2
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.alphaOf(root.accent, 0.35) }
            GradientStop { position: 1; color: root.accent }
          }
          Behavior on width { enabled: !g.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        // Notch at 50: the look as designed.
        Rectangle {
          x: parent.width / 2 - 1; y: -Style.space(4)
          width: 2; height: Style.space(4); radius: 1
          color: root.alphaOf(root.fg, 0.35)
        }
      }
      // Pebble thumb, raised above the cut.
      RectangularShadow {
        anchors.fill: thumb
        offset.y: 2; blur: 6; radius: thumb.radius
        color: Qt.rgba(0, 0, 0, 0.5)
      }
      Rectangle {
        id: thumb
        width: Style.space(22); height: width; radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(4) + (parent.width - Style.space(8)) * g.progress - width / 2
        Behavior on x { enabled: !g.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        gradient: Gradient {
          GradientStop { position: 0; color: "#FFFFFF" }
          GradientStop { position: 1; color: Qt.darker(root.fg, 1.08) }
        }
        border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.18)
        scale: grooveMouse.pressed ? 1.12 : grooveMouse.containsMouse ? 1.05 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(6); height: width; radius: width / 2
          color: root.accent
        }
      }
      MouseArea {
        id: grooveMouse
        anchors.fill: parent
        anchors.topMargin: -Style.space(4); anchors.bottomMargin: -Style.space(4)
        enabled: g.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function valueAt(x) { return Math.round(Math.max(0, Math.min(1, (x - Style.space(4)) / (width - Style.space(8)))) * 100) }
        function preview(v) { g.live = v; const d = Object.assign({}, root.draft); d.intensity = v; root.draft = d }
        onEntered: root.selectedRow = 3
        onPressed: function(m) { g.dragging = true; root.selectedRow = 3; preview(valueAt(m.x)) }
        onPositionChanged: function(m) { if (g.dragging) preview(valueAt(m.x)) }
        onReleased: { g.dragging = false; root.commit("intensity", g.live) }
        onWheel: function(w) { var v = Math.max(0, Math.min(100, g.live + (w.angleDelta.y > 0 ? 5 : -5))); g.live = v; root.commit("intensity", v) }
      }
    }
    Item {
      width: parent.width
      height: scaleLeft.implicitHeight
      Text { id: scaleLeft; text: "Flat"; color: root.alphaOf(root.fg, 0.4); font.family: root.family; font.pixelSize: Style.font.caption - 1 }
      Text { anchors.horizontalCenter: parent.horizontalCenter; text: "As designed"; color: root.alphaOf(root.fg, 0.4); font.family: root.family; font.pixelSize: Style.font.caption - 1 }
      Text { anchors.right: parent.right; text: root.raised ? "Twice as high" : "Twice as deep"; color: root.alphaOf(root.fg, 0.4); font.family: root.family; font.pixelSize: Style.font.caption - 1 }
    }
  }

  // Slim slider row for Details: label · value · 6px track; previews live,
  // applies on release.
  component Slider: Column {
    id: sl
    property var spec: ({})
    property int row: 0
    property bool dragging: false
    property real live: Number(root.prof[spec.key] || 0)
    readonly property real range: Math.max(0.0001, spec.max - spec.min)
    readonly property real progress: Math.max(0, Math.min(1, (live - spec.min) / range))
    spacing: Style.space(7)
    enabled: root.loaded
    Connections { target: root; function onProfChanged() { if (!sl.dragging) sl.live = Number(root.prof[sl.spec.key] || 0) } }

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
        text: root.fmt(sl.spec, sl.live)
        color: root.alphaOf(root.fg, 0.6)
        font.family: root.mono; font.pixelSize: Style.font.body
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
          color: root.alphaOf(root.fg, 0.78)
          Behavior on width { enabled: !sl.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }
      MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: -Style.space(4); anchors.bottomMargin: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function valueAt(x) {
          var f = Math.max(0, Math.min(1, x / track.width))
          var v = Math.round((sl.spec.min + f * sl.range) / sl.spec.step) * sl.spec.step
          return Math.round(Math.max(sl.spec.min, Math.min(sl.spec.max, v)) * 1000) / 1000
        }
        function preview(v) { sl.live = v; const d = Object.assign({}, root.draft); d[sl.spec.key] = v; root.draft = d }
        onEntered: root.selectedRow = sl.row
        onPressed: function(m) { sl.dragging = true; root.selectedRow = sl.row; preview(valueAt(m.x)) }
        onPositionChanged: function(m) { if (sl.dragging) preview(valueAt(m.x)) }
        onReleased: { sl.dragging = false; root.commit(sl.spec.key, sl.live) }
        onWheel: function(w) {
          var v = Math.round(Math.max(sl.spec.min, Math.min(sl.spec.max, sl.live + (w.angleDelta.y > 0 ? 1 : -1) * sl.spec.step)) * 1000) / 1000
          sl.live = v; root.commit(sl.spec.key, v)
        }
      }
    }
  }
}
