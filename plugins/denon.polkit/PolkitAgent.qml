import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PolkitModel.js" as PolkitModel

Item {
  id: root

  property string fontFamily: Style.font.menuFamily
  // Bound to the central [polkit] section in shell.toml via Commons.Color.qml.
  property color accent: Commons.Color.polkit.accent
  property color background: Commons.Color.polkit.background
  property color foreground: Commons.Color.polkit.text
  property color border: Commons.Color.polkit.border
  property color borderError: Commons.Color.polkit.borderError
  property var borderSpec: Border.surfaceSpec("polkit", errorFlash ? "border-error" : "border", errorFlash ? borderError : border, Math.max(1, Style.space(2)), "border-alpha")
  property color scrim: Commons.Color.polkit.scrim
  readonly property int cornerRadius: Style.space(18)
  // Glass surfaces: header (lock tile, title, request) above an inset field.
  readonly property int headerHeight: Style.space(36)
  readonly property int headerGap: Style.space(14)
  property int contentMargin: Style.space(16)
  property int fieldHeight: Math.max(Style.space(42), Style.spacing.controlHeight)

  property bool closing: false
  property bool submitted: false
  property string currentMessage: ""
  property string currentPrompt: ""
  property string currentSupplementary: ""
  property bool responseRequired: false
  property bool responseVisible: false
  property bool failed: false
  property bool errorFlash: false
  // pam_fprintd appears in the polkit PAM stack (a sensor is enrolled).
  property bool fingerprintConfigured: false
  // Lid shut right now — the reader is physically unreachable, so we fall back
  // to the password even when a sensor is enrolled. Refreshed per request.
  property bool laptopClosed: false
  property int shakeOffset: 0
  property int submittedLength: 0

  readonly property bool dialogVisible: polkitAgent.isActive || closing
  // We show one method at a time. Fingerprint owns the dialog while PAM is
  // waiting on the reader (lid open, sensor enrolled); the moment PAM asks for
  // a password — including immediately when the lid is shut and the clamshell
  // gate skips pam_fprintd — we switch to the password field instead.
  readonly property bool fingerprintMode: fingerprintConfigured && !laptopClosed && dialogVisible && !responseRequired && !submitted && !errorFlash
  // P4 "dot capsule": one pill (lock · dots · →) with a single context line
  // under it. Fingerprint mode collapses the pill to a circle.
  readonly property int cardHeight: Style.space(56)
  readonly property int cardWidth: fingerprintMode ? cardHeight : Math.min(Style.space(340), Math.max(Style.space(260), panel.width - Style.gapsOut * 2))
  readonly property int maxDots: 14

  // "Authentication is required to manage X." -> "Password to manage X"
  function contextLine(message) {
    var text = String(message || "").trim()
    var m = text.match(/^Authentication is (?:needed|required) to (.+?)\.?$/i)
    if (m && !/^run /i.test(m[1])) return (fingerprintMode ? "Touch the reader to " : "Password to ") + m[1]
    return authorizationLabel(text)
  }

  function authorizationLabel(message) {
    return PolkitModel.authorizationLabel(message)
  }

  function loadPamConfig(raw) {
    fingerprintConfigured = PolkitModel.fingerprintConfiguredFromPamConfig(raw)
  }

  function refreshLidState() {
    if (!laptopClosedProc.running) laptopClosedProc.running = true
  }

  function resetSnapshot() {
    currentMessage = ""
    currentPrompt = ""
    currentSupplementary = ""
    responseRequired = false
    responseVisible = false
    failed = false
    errorFlash = false
    submitted = false
    passwordInput.text = ""
  }

  function syncFromFlow() {
    var flow = polkitAgent.flow
    if (!flow) return

    currentMessage = String(flow.message || "Authentication is needed...")
    currentPrompt = String(flow.inputPrompt || "")
    currentSupplementary = String(flow.supplementaryMessage || "")
    responseRequired = !!flow.isResponseRequired
    responseVisible = !!flow.responseVisible
    failed = !!flow.failed

    if (responseRequired) submitted = false
  }

  function beginFlow() {
    closeTimer.stop()
    closing = false
    submitted = false
    passwordInput.text = ""
    refreshLidState()
    syncFromFlow()
    Qt.callLater(refocus)
  }

  function refocus() {
    if (!dialogVisible) return
    // In fingerprint mode there is no field to type into — park focus on the
    // key catcher so Escape still cancels; otherwise focus the password field.
    if (fingerprintMode) keyCatcher.forceActiveFocus()
    else passwordInput.forceActiveFocus()
  }

  function submitResponse() {
    var flow = polkitAgent.flow
    if (!flow || !flow.isResponseRequired) return
    submitted = true
    errorFlash = false
    submittedLength = passwordInput.text.length
    flow.submit(passwordInput.text)
    passwordInput.text = ""
    keyCatcher.forceActiveFocus()
  }

  function cancelRequest() {
    var flow = polkitAgent.flow
    passwordInput.text = ""
    submitted = false
    closing = true
    closeTimer.restart()
    if (flow) flow.cancelAuthenticationRequest()
  }

  function triggerFailureFeedback() {
    submitted = false
    errorFlash = true
    passwordInput.text = ""
    errorTimer.restart()
    shakeAnimation.restart()
    Qt.callLater(refocus)
  }

  Timer {
    id: closeTimer
    interval: 300
    repeat: false
    onTriggered: {
      closing = false
      resetSnapshot()
    }
  }

  Timer {
    id: errorTimer
    interval: 1200
    repeat: false
    onTriggered: root.errorFlash = false
  }

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
  }
  FileView {
    path: "/etc/pam.d/polkit-1"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPamConfig(text())
    onLoadFailed: root.fingerprintConfigured = false
    onFileChanged: reload()
  }

  Process {
    id: laptopClosedProc
    command: ["bash", "-c", "omarchy-hw-laptop-closed && echo closed || echo open"]
    stdout: StdioCollector { id: laptopClosedOut; waitForEnd: true }
    onExited: root.laptopClosed = String(laptopClosedOut.text || "").trim() === "closed"
  }

  PolkitAgent {
    id: polkitAgent
    path: "/org/omarchy/PolkitAgent"

    onAuthenticationRequestStarted: root.beginFlow()
    onIsActiveChanged: {
      if (isActive) root.syncFromFlow()
      else if (!root.closing) root.resetSnapshot()
    }
    onIsRegisteredChanged: {
      if (isRegistered) console.log("omarchy polkit agent registered")
      else console.warn("omarchy polkit agent is not registered; another agent may be running")
    }
  }

  Connections {
    target: polkitAgent.flow

    function onIsResponseRequiredChanged() {
      root.syncFromFlow()
      if (!polkitAgent.flow || !polkitAgent.flow.isResponseRequired) passwordInput.text = ""
      Qt.callLater(root.refocus)
    }

    function onInputPromptChanged() { root.syncFromFlow() }
    function onResponseVisibleChanged() { root.syncFromFlow() }
    function onSupplementaryMessageChanged() { root.syncFromFlow() }
    function onFailedChanged() { root.syncFromFlow() }

    function onAuthenticationFailed() {
      root.syncFromFlow()
      root.triggerFailureFeedback()
    }

    function onAuthenticationSucceeded() {
      root.closing = true
      closeTimer.restart()
    }

    function onAuthenticationRequestCancelled() {
      root.closing = true
      closeTimer.restart()
    }
  }

  PanelWindow {
    id: panel
    visible: root.dialogVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "inferna-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.refocus()
    }

    RectangularShadow {
      x: card.x; y: card.y + 8
      width: card.width; height: card.height
      radius: card.radius
      blur: 36
      spread: -6
      color: Qt.rgba(0, 0, 0, Commons.Color.background.hslLightness > 0.5 ? 0.16 : 0.4)
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: height / 2
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.shakeOffset
      color: root.background
      borderSpec: root.borderSpec
      Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.cancelRequest()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.responseRequired) root.submitResponse()
            event.accepted = true
          }
        }
      }

      // Fingerprint mode: the pill becomes a circle holding the sensor glyph.
      OpticalGlyph {
        anchors.centerIn: parent
        width: Math.round(root.cardHeight * 0.5)
        height: width
        visible: root.fingerprintMode
        text: "\udb80\ude37"
        fontFamily: root.fontFamily
        fontSize: Math.round(root.cardHeight * 0.5)
        color: root.errorFlash ? Commons.Color.polkit.textError : root.accent
      }

      Item {
        id: pillRow
        visible: !root.fingerprintMode
        anchors.fill: parent
        anchors.leftMargin: Style.space(20)
        anchors.rightMargin: Style.space(10)

        Text {
          id: lockGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "\uf023"
          color: root.errorFlash ? Commons.Color.polkit.textError : root.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
        }

        // The real input stays invisible; dots below mirror its length.
        TextInput {
          id: passwordInput
          anchors.left: lockGlyph.right
          anchors.leftMargin: Style.space(14)
          anchors.right: goButton.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          verticalAlignment: TextInput.AlignVCenter
          activeFocusOnPress: true
          clip: true
          font.family: root.fontFamily
          font.pixelSize: Style.font.title + 1
          echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
          passwordCharacter: "\u2022"
          // Visible text only for non-secret prompts; otherwise dots draw it.
          color: root.responseVisible ? root.foreground : "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorVisible: false
          cursorDelegate: Item {}
          readOnly: root.submitted || root.errorFlash
          enabled: root.dialogVisible
          onAccepted: root.submitResponse()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelRequest()
              event.accepted = true
            }
          }
        }

        Row {
          id: dots
          visible: !root.responseVisible
          anchors.left: passwordInput.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(9)
          Repeater {
            model: Math.min(root.submitted ? root.submittedLength : passwordInput.text.length, root.maxDots)
            Rectangle {
              width: Style.space(9); height: width; radius: width / 2
              anchors.verticalCenter: parent ? parent.verticalCenter : undefined
              color: root.errorFlash ? Commons.Color.polkit.textError : root.foreground
              opacity: root.submitted ? checkingPulse.value : 1
              scale: 0.4
              Component.onCompleted: scale = 1
              Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
            }
          }
          // Caret: accent bar after the last dot.
          Rectangle {
            id: caret
            width: Math.max(2, Style.space(2)); height: Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            visible: passwordInput.activeFocus && !root.submitted && !root.errorFlash
            SequentialAnimation on opacity {
              running: caret.visible
              loops: Animation.Infinite
              NumberAnimation { from: 1; to: 0.15; duration: 520; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.15; to: 1; duration: 520; easing.type: Easing.InOutSine }
            }
          }
        }

        // Placeholder / status in the pill when nothing is typed.
        Text {
          visible: passwordInput.text.length === 0 && !root.submitted
          anchors.left: passwordInput.left
          anchors.leftMargin: passwordInput.activeFocus && !root.submitted && !root.errorFlash ? Style.space(10) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: root.errorFlash ? "Wrong password" : (root.submitted ? "Checking…" : (root.currentPrompt.trim() && !/^password:?$/i.test(root.currentPrompt.trim()) ? root.currentPrompt.trim().replace(/:$/, "") : "Password"))
          color: root.errorFlash ? Commons.Color.polkit.textError : root.foreground
          opacity: root.errorFlash ? 1 : 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        MouseArea {
          anchors.fill: passwordInput
          onClicked: passwordInput.forceActiveFocus()
        }

        Rectangle {
          id: goButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(36); height: width; radius: width / 2
          color: root.errorFlash ? Commons.Color.polkit.textError : root.accent
          opacity: passwordInput.text.length > 0 || root.submitted ? 1 : 0.45
          Behavior on opacity { NumberAnimation { duration: 140 } }
          Text {
            anchors.centerIn: parent
            text: root.submitted ? "\u2026" : "\u2192"
            color: Commons.Color.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.title + 1
            font.weight: Font.Bold
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: passwordInput.text.length > 0 && !root.submitted
            onClicked: root.submitResponse()
          }
        }
      }
    }

    // One context line under the pill (what the password is for), on its own
    // small frosted pill so it stays legible over any window.
    Rectangle {
      id: contextPill
      anchors.top: card.bottom
      anchors.topMargin: Style.space(10)
      anchors.horizontalCenter: card.horizontalCenter
      anchors.horizontalCenterOffset: root.shakeOffset
      width: Math.min(contextText.implicitWidth, Style.space(440)) + Style.space(24)
      height: contextText.height + Style.space(12)
      radius: Style.space(12)
      color: Util.alpha(root.background, 0.82)
      visible: contextText.text.length > 0
      Text {
        id: contextText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, Style.space(440))
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.errorFlash ? "Wrong password — try again" : root.contextLine(root.currentMessage)
        color: root.errorFlash ? Commons.Color.polkit.textError : Util.alpha(root.foreground, 0.82)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall + 1
      }
    }

    // Shared pulse for the dots while PAM checks the password.
    QtObject {
      id: checkingPulse
      property real value: 1
      property SequentialAnimation anim: SequentialAnimation {
        running: root.submitted
        loops: Animation.Infinite
        onRunningChanged: if (!running) checkingPulse.value = 1
        NumberAnimation { target: checkingPulse; property: "value"; from: 1; to: 0.3; duration: 420; easing.type: Easing.InOutSine }
        NumberAnimation { target: checkingPulse; property: "value"; from: 0.3; to: 1; duration: 420; easing.type: Easing.InOutSine }
      }
    }
  }
}
