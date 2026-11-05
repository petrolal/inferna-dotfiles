import "../denon.bar/panels" as Motion
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "denon.tray"

  // Expanded while the pointer is on the tray's drawer block, while one of
  // the hidden icons' menus is open (its drawer overlay covers the rail and
  // steals hover — collapsing then slid the icons away under their own menu),
  // or briefly after an open drawer handed the arrow the pointer.
  property bool drawerHover: false
  // The arrow's own MouseArea claims hover, so the drawer block's
  // HoverHandler never sees a pointer resting on the arrow itself.
  property bool arrowHover: false
  property bool arrowHold: false
  readonly property bool wantExpanded: drawerHover || arrowHover || arrowHold
    || (trayMenuOpen && !!activeTrayAnchor && activeTrayAnchor.inDrawer === true)
  // Open at once; close after a short grace so crossing from the arrow to
  // the icons (two hover owners) never flickers it shut.
  property bool expanded: false
  onWantExpandedChanged: {
    if (wantExpanded) { collapseTimer.stop(); expanded = true }
    else collapseTimer.restart()
  }
  Timer { id: collapseTimer; interval: 150; onTriggered: if (!root.wantExpanded) root.expanded = false }
  onDrawerHoverChanged: if (!drawerHover && !arrowHover) arrowHold = false
  onArrowHoverChanged: if (!drawerHover && !arrowHover) arrowHold = false
  // A hand-off from an open drawer sets arrowHold without the drawer block
  // ever seeing the pointer; if it never arrives (pointer already gone), let go.
  Timer {
    interval: 600
    repeat: true
    running: root.arrowHold && !root.drawerHover && !root.arrowHover
    onTriggered: root.arrowHold = false
  }
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: 0
  readonly property int trayJoinGap: 0
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0
  // Match Waybar's group/tray-expander drawer transition-duration.
  readonly property int animationDuration: 600
  property real revealProgress: expanded ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    trayMenuFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
    snipOpen = false
  }

  Timer { id: trayResetTimer; interval: 220; onTriggered: if (!root.trayMenuOpen) root.resetTrayMenu() }

  // Snip publishes no D-Bus menu: snipd pops its own platform menu, which on
  // Wayland lands unstyled in the screen's top-left corner. Under the Pebble
  // Shell the Snip icon opens this Tide drawer instead, driving the snip CLI.
  property bool snipOpen: false
  property Item snipAnchor: null
  property bool snipRecording: false
  property Item snipItemRef: null
  // `inferna-shell denon.tray.snip open|close|toggle` (keyboard / testing).
  IpcHandler {
    target: "denon.tray.snip"
    function open(): string { root.openSnip(root.snipItemRef); return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string { if (root.snipOpen) root.close(); else root.openSnip(root.snipItemRef); return "ok" }
    function icon(): string { var r = root.snipItemRef; return JSON.stringify(r ? { icon: String(r.modelData.icon), status: r.iconStatusForDebug, visible: r.visible, w: r.width, h: r.height } : null) }
    function state(): string { return JSON.stringify({ snipOpen: root.snipOpen, trayMenuOpen: root.trayMenuOpen, manage: root.managePopupOpen, expanded: root.expanded, drawerHover: root.drawerHover, arrowHover: root.arrowHover, arrowHold: root.arrowHold, reveal: root.revealProgress, active: Motion.PanelMotion.active ? (Motion.PanelMotion.active === snipPopup ? "snip" : Motion.PanelMotion.active === trayMenuPopup ? "traymenu" : "other") : "", activePopoutIsTray: !!(root.bar && root.bar.activePopout === root) }) }
  }
  function isSnip(item) { return !!item && String(item.id || "").toLowerCase() === "snip" }
  function openSnip(anchorItem) {
    trayMenuOpen = false
    snipAnchor = anchorItem
    if (snipOpen && Motion.PanelMotion.active !== snipPopup) snipOpen = false
    snipOpen = true
    snipStatus.running = false
    snipStatus.running = true
  }
  // Close the drawer first so it is not in the capture, then run.
  property var snipPending: null
  function runSnip(args) {
    snipPending = ["snip"].concat(args)
    root.close()
    snipRunTimer.restart()
  }
  Timer {
    id: snipRunTimer
    interval: 260
    onTriggered: if (root.snipPending) { Quickshell.execDetached(root.snipPending); root.snipPending = null }
  }
  Process {
    id: snipStatus
    command: ["snip", "--json", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var r = JSON.parse(text).result; root.snipRecording = !!(r && r.recording) } catch (e) { root.snipRecording = false }
      }
    }
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (Motion.PanelMotion.tide && isSnip(item)) { openSnip(anchorItem); return }
    snipOpen = false
    if (!item || !item.menu) {
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    if (trayMenuOpen && Motion.PanelMotion.active !== trayMenuPopup) trayMenuOpen = false
    trayMenuOpen = true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to IconImage; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  function persistTrayState(pinned, hidden) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var id = root.moduleName || "omarchy.tray"
    root.bar.shell.updateEntryInline(id, { id: id, pinned: pinned, hidden: hidden })
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistTrayState(p, h)
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistTrayState(p, h)
  }

  visible: pinnedItems.length > 0 || drawerCount > 0
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int pinnedWidth: pinnedRow.implicitWidth
      readonly property int drawerBlockWidth: root.allItems.length > 0 ? expandIcon.implicitWidth + root.drawerExtent : 0

      implicitWidth: pinnedWidth + drawerBlockWidth
      implicitHeight: root.barSize

      // Mask out the empty area the collapsed drawer reserves for its slide-in,
      // so hovering it doesn't trigger expand and clicks pass through.
      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.y < 0 || point.y > horizontalTrayRoot.height) return false
          // Drawer reveals leftward; chevron sits at the right end when collapsed
          // and slides left as it opens. The visible region starts at the chevron.
          var chevronX = root.drawerExtent - root.revealExtent
          if (point.x >= chevronX && point.x <= horizontalTrayRoot.drawerBlockWidth) return true
          // Pinned items, placed to the right of the drawer block.
          var pinnedStart = horizontalTrayRoot.drawerBlockWidth
          return point.x >= pinnedStart && point.x <= horizontalTrayRoot.implicitWidth
        }
      }

      Item {
        id: drawerArea
        x: 0
        width: horizontalTrayRoot.drawerBlockWidth
        height: root.barSize
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.drawerHover = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          // Pebble Shell: hovering the arrow through an open drawer closes
          // that drawer and reveals the hidden tray icons.
          readonly property bool hoverReady: Motion.PanelMotion.tide && root.allItems.length > 0
          function openHover() { Motion.PanelMotion.close(); root.arrowHold = true }
          onTooltipHoveredChanged: root.arrowHover = tooltipHovered
          Component.onCompleted: Motion.PanelMotion.registerHoverTarget(expandIcon)
          Component.onDestruction: Motion.PanelMotion.unregisterHoverTarget(expandIcon)
          width: implicitWidth
          height: implicitHeight
          x: root.drawerExtent - root.revealExtent
          text: "\uf053"
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          x: expandIcon.width
          anchors.verticalCenter: parent.verticalCenter
          width: root.drawerExtent
          height: root.barSize
          clip: true

          Row {
            id: trayIcons
            x: root.drawerExtent - root.revealExtent
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem { inDrawer: true }
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: drawerArea.x + horizontalTrayRoot.drawerBlockWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int pinnedHeight: pinnedCol.implicitHeight
      readonly property int drawerBlockHeight: root.allItems.length > 0 ? expandIcon.implicitHeight + root.drawerExtent : 0

      implicitWidth: root.barSize
      implicitHeight: pinnedHeight + drawerBlockHeight

      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.x < 0 || point.x > verticalTrayRoot.width) return false
          var chevronY = root.drawerExtent - root.revealExtent
          if (point.y >= chevronY && point.y <= verticalTrayRoot.drawerBlockHeight) return true
          var pinnedStart = verticalTrayRoot.drawerBlockHeight
          return point.y >= pinnedStart && point.y <= verticalTrayRoot.implicitHeight
        }
      }

      Item {
        id: drawerArea
        y: 0
        width: root.barSize
        height: verticalTrayRoot.drawerBlockHeight
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.drawerHover = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          // Pebble Shell: hovering the arrow through an open drawer closes
          // that drawer and reveals the hidden tray icons.
          readonly property bool hoverReady: Motion.PanelMotion.tide && root.allItems.length > 0
          function openHover() { Motion.PanelMotion.close(); root.arrowHold = true }
          onTooltipHoveredChanged: root.arrowHover = tooltipHovered
          Component.onCompleted: Motion.PanelMotion.registerHoverTarget(expandIcon)
          Component.onDestruction: Motion.PanelMotion.unregisterHoverTarget(expandIcon)
          width: implicitWidth
          height: implicitHeight
          // Pebble Shell: the arrow stays put just above the pinned icons and
          // flips to point down; the hidden icons rise out of it above. (It
          // used to fly up and slide three icons under a resting pointer.)
          y: Motion.PanelMotion.tide ? root.drawerExtent : root.drawerExtent - root.revealExtent
          z: 2
          text: "\uf053"
          textRotation: 90 + (Motion.PanelMotion.tide ? 180 * root.revealProgress : 0)
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          y: Motion.PanelMotion.tide ? 0 : expandIcon.height
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: root.drawerExtent
          clip: true

          Column {
            id: trayIcons
            y: root.drawerExtent - root.revealExtent
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap
            layer.enabled: true
            // Clipping hides the collapsed icons but does not stop them taking
            // the pointer: keep them out of hit-testing until they're revealed.
            visible: !Motion.PanelMotion.tide || root.revealProgress > 0.02

            Repeater {
              model: root.drawerItems
              TrayItem { inDrawer: true }
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: drawerArea.y + verticalTrayRoot.drawerBlockHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Motion.PopupPanel {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(300))
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

    Column {
      id: manageColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "Tray icons"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: "Pinned icons stay visible. Hidden icons never show."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text {
        visible: root.allItems.length === 0
        text: "No tray items reporting."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Repeater {
        model: root.allItems
        delegate: Item {
          id: rowRoot
          required property var modelData
          required property int index
          width: manageColumn.width
          implicitHeight: 28

          readonly property string itemId: String(modelData.id || "")
          readonly property string displayName: {
            var t = String(modelData.title || "").trim()
            if (t) return t
            var tt = String(modelData.tooltipTitle || "").trim()
            if (tt) return tt
            var id = String(modelData.id || "")
            var slash = id.lastIndexOf("/")
            return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
          }
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1

          TrayIcon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: 16
            height: 16
            icon: rowRoot.modelData.icon
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.space(8)
            text: rowRoot.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: rowPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(rowRoot.itemId)
          }

          Button {
            id: rowHideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: rowPinBtn.left
            anchors.rightMargin: Style.space(6)
            iconText: "\uf06e"
            text: rowRoot.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(rowRoot.itemId)
          }
        }
      }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  Motion.PopupPanel {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // The card fades out over 140ms (visible stays true for that whole time --
    // see PopupCard's own visible: open || card.opacity > 0), so resetting on
    // "open" would swap a live submenu for the root menu mid-fade: a visible
    // flash, and a resize/reposition if the two have different geometry. Wait
    // for the fade to actually finish. Switching to a different tray item
    // still resets immediately, from openTrayMenu() itself.
    // As a rail drawer it has no fade-out visibility to watch; reset once
    // the close has played out instead.
    onOpenChanged: if (!open) trayResetTimer.restart()
    padding: Style.space(8)
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    // Column skips invisible children but keeps reporting their height, so
    // read the header's extent through its own visibility.
    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      // Header for a drilled-into submenu: names where we are and walks back
      // out. Pinned above the Flickable rather than scrolling with the rows,
      // so the way back stays reachable in a submenu taller than the card.
      // Only present below the root level, so the root menu is unchanged.
      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        spacing: 0

        Item {
          id: menuBackRow
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Style.space(8)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "\u2039"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            text: root.currentTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuLevelSettling) return
              // Reset before the model swap so the parent level shows from
              // the top (same ordering as the row delegate below).
              trayMenuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(11)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Util.alpha(root.foreground, 0.1)
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - trayMenuPopup.menuHeaderHeight
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width
          spacing: 0

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              // Both only ever describe the root menu; inside a submenu the first
              // rows are real entries and must not be swallowed.
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              visible: !hiddenRow
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Util.alpha(root.foreground, 0.1)
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Style.space(8)
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                id: menuIcon
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels: IconImage uses the logical size,
                // which leaves PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.space(8)
                text: menuRow.rowText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                text: "\u203a"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (menuRow.modelData.hasChildren) {
                    // Reset scroll BEFORE swapping the model: the swap destroys
                    // this delegate synchronously and ids stop resolving after.
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ Snip drawer
  // Tide card: a light title, four big hairline capture buttons, a Record
  // row that turns into Stop while recording, and quiet sentence-case rows.
  readonly property color snipAccent: Commons.Color.background.hslLightness < 0.5
    ? Qt.hsla(Commons.Color.accent.hslHue, Commons.Color.accent.hslSaturation, Math.max(Commons.Color.accent.hslLightness, 0.62), 1)
    : Commons.Color.accent

  Motion.PopupPanel {
    id: snipPopup
    anchorItem: root.snipAnchor || root
    owner: root
    bar: root.bar
    open: root.snipOpen
    padding: Style.space(18)
    contentWidth: snipPopup.fittedContentWidth(Style.space(300))
    contentHeight: snipPopup.fittedContentHeight(snipBody.implicitHeight, Style.space(700))

    Column {
      id: snipBody
      width: parent.width
      spacing: 0

      Item {
        width: parent.width
        height: Style.space(34)
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Snip"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(22)
          font.weight: Font.Light
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Rectangle {
            visible: root.snipRecording
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7); height: width; radius: width / 2
            color: Commons.Color.red !== undefined ? Commons.Color.red : root.snipAccent
            SequentialAnimation on opacity {
              running: root.snipRecording && root.snipOpen
              loops: Animation.Infinite
              NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.snipRecording ? "Recording" : "Capture"
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // Four big capture buttons.
      Row {
        width: parent.width
        topPadding: Style.space(8)
        bottomPadding: Style.space(10)
        Repeater {
          model: [["area", "Area", ["area"]], ["window", "Window", ["window"]], ["screen", "Screen", ["fullscreen"]], ["text", "Text", ["text"]]]
          delegate: Item {
            id: bigBtn
            required property var modelData
            width: snipBody.width / 4
            height: Style.space(74)
            Rectangle {
              id: bigDisc
              anchors.horizontalCenter: parent.horizontalCenter
              y: 0
              width: Style.space(48); height: width; radius: width / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, bigMouse.containsMouse ? 0.1 : 0.05)
              scale: bigMouse.pressed ? 0.92 : bigMouse.containsMouse ? 1.06 : 1
              Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
              Behavior on color { ColorAnimation { duration: 140 } }
              SnipIcon { anchors.centerIn: parent; name: bigBtn.modelData[0]; size: Style.space(22); lit: bigMouse.containsMouse }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: bigDisc.bottom
              anchors.topMargin: Style.space(7)
              text: bigBtn.modelData[1]
              color: bigMouse.containsMouse ? root.snipAccent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              Behavior on color { ColorAnimation { duration: 140 } }
            }
            MouseArea {
              id: bigMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runSnip(bigBtn.modelData[2])
            }
          }
        }
      }

      SnipRow { icon: root.snipRecording ? "stop" : "record"; label: root.snipRecording ? "Stop recording" : "Record screen"; hint: "Alt+Print"; strong: true; args: root.snipRecording ? ["record", "stop"] : ["record"] }
      SnipRow { visible: !root.snipRecording; icon: "gif"; label: "Record a GIF"; args: ["record", "--gif"] }

      SnipRule {}
      SnipRow { icon: "spark"; label: "All-in-one"; args: ["all-in-one"] }
      SnipRow { icon: "previous"; label: "Previous area"; args: ["previous"] }
      SnipRow { icon: "timer"; label: "Self-timer"; hint: "3 s"; args: ["area", "--delay", "3"] }
      SnipRow { icon: "scroll"; label: "Scrolling capture"; args: ["scroll"] }

      SnipRule {}
      SnipRow { icon: "history"; label: "Capture history"; hint: "Super+Ctrl+Shift+S"; args: ["history"] }
      SnipRow { icon: "restore"; label: "Restore last closed"; args: ["restore"] }
      SnipRow { icon: "clipboard"; label: "Edit clipboard image"; args: ["edit", "--clipboard"] }
      SnipRow { icon: "pin"; label: "Show or hide pins"; args: ["pins", "toggle"] }
      SnipRow { icon: "clutter"; label: "Hide desktop clutter"; args: ["desktop", "toggle"] }

      SnipRule {}
      Row {
        spacing: Style.space(18)
        leftPadding: Style.space(2)
        Repeater {
          model: [["Settings", ["settings"]], ["About", ["settings", "about"]], ["Quit Snip", ["quit"]]]
          delegate: Text {
            id: footLink
            required property var modelData
            text: modelData[0]
            color: footMouse.containsMouse ? root.snipAccent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            topPadding: Style.space(6)
            Behavior on color { ColorAnimation { duration: 140 } }
            MouseArea { id: footMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runSnip(footLink.modelData[1]) }
          }
        }
      }
    }
  }

  component SnipIcon: Item {
    id: snipIcon
    property string name: ""
    property real size: Style.space(16)
    property bool lit: false
    width: size; height: size
    Image {
      id: snipIconImage
      visible: false
      anchors.fill: parent
      source: snipIcon.name ? Qt.resolvedUrl("icons/" + snipIcon.name + ".svg") : ""
      sourceSize.width: snipIcon.size * Screen.devicePixelRatio
      sourceSize.height: snipIcon.size * Screen.devicePixelRatio
    }
    MultiEffect {
      anchors.fill: parent
      source: snipIconImage
      colorization: 1
      colorizationColor: snipIcon.lit ? root.snipAccent : root.foreground
      opacity: snipIcon.lit ? 1 : 0.72
      Behavior on colorizationColor { ColorAnimation { duration: 140 } }
    }
  }

  component SnipRule: Item {
    width: snipBody.width
    height: Style.space(13)
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width; height: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }
  }

  component SnipRow: Item {
    id: snipRow
    property string icon: ""
    property string label: ""
    property string hint: ""
    property bool strong: false
    property var args: []
    width: snipBody.width
    height: visible ? Style.space(34) : 0
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 3; radius: 1.5
      height: rowMouse.containsMouse ? Style.space(18) : 0
      color: root.snipAccent
      Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    }
    SnipIcon {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      name: snipRow.icon
      size: Style.space(17)
      lit: rowMouse.containsMouse
    }
    Text {
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.space(13)
      anchors.right: hintText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: snipRow.label
      color: rowMouse.containsMouse ? root.snipAccent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.space(snipRow.strong ? 15 : 14)
      font.weight: snipRow.strong ? Font.Medium : Font.Normal
      elide: Text.ElideRight
      Behavior on color { ColorAnimation { duration: 140 } }
    }
    Text {
      id: hintText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: snipRow.hint
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.runSnip(snipRow.args)
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)
    readonly property int imageStatus: trayIconImage.status

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size,
      // which leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Always a hidden layer drawn through the effect below. Toggling
      // layer.enabled/visible when an app swaps its icon at runtime (Snip goes
      // snip-tray-recording -> snip-tray-symbolic after a recording) left the
      // effect sampling a dead texture: the icon vanished until a restart.
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      // Symbolic icons are recolored to the bar foreground; full-colour
      // icons pass through untouched.
      colorization: trayIconRoot.symbolic ? 1.0 : 0.0
      colorizationColor: root.foreground
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData
    property bool inDrawer: false
    // Pebble Shell: an icon with a menu slides its menu out as a drawer on
    // hover, like every other rail icon (drawer icons only once revealed).
    readonly property bool snipItem: Motion.PanelMotion.tide && root.isSnip(modelData)
    readonly property int iconStatusForDebug: itemIcon.imageStatus
    readonly property bool hoverReady: Motion.PanelMotion.tide && visible && !!modelData && (!!modelData.menu || snipItem)
      && (!inDrawer || root.revealProgress > 0.9)
    readonly property bool menuShown: snipItem ? (root.snipOpen && root.snipAnchor === trayItemRoot)
      : (root.trayMenuOpen && root.activeTrayItem === modelData)
    // Only trust "already shown" when its drawer really is the one on screen;
    // a stale open flag used to swallow every later hover.
    readonly property bool reallyShown: menuShown && !!Motion.PanelMotion.active
      && Motion.PanelMotion.active === (snipItem ? snipPopup : trayMenuPopup)
    function openHover() {
      if (trayItemRoot.reallyShown) return
      if (trayItemRoot.snipItem) root.openSnip(trayItemRoot)
      else root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, null)
    }
    // An icon that finishes sliding in under a resting pointer opens then,
    // instead of waiting for the pointer to move.
    onHoverReadyChanged: if (hoverReady && mouseArea.containsMouse) Motion.PanelMotion.queueTarget(trayItemRoot)
    Component.onCompleted: { Motion.PanelMotion.registerHoverTarget(trayItemRoot); if (snipItem && !inDrawer) root.snipItemRef = trayItemRoot }
    Component.onDestruction: Motion.PanelMotion.unregisterHoverTarget(trayItemRoot)

    Rectangle {
      visible: Motion.PanelMotion.tide
      anchors.centerIn: parent
      width: Style.space(28); height: width; radius: Style.space(8)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      opacity: mouseArea.containsMouse ? 1 : trayItemRoot.menuShown ? 0.6 : 0
      scale: mouseArea.containsMouse || trayItemRoot.menuShown ? 1 : 0.86
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
    }

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    TrayIcon {
      id: itemIcon
      anchors.centerIn: parent
      width: Style.space(12)
      height: Style.space(12)
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        if (trayItemRoot.hoverReady) Motion.PanelMotion.queueTarget(trayItemRoot)
        else if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      }
      onExited: {
        Motion.PanelMotion.cancelTarget(trayItemRoot)
        if (root.bar) root.bar.hideTooltip(trayItemRoot)
      }
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.snipItem) {
          // Hover already opened it: the click commits (keeps it open), like
          // every other rail icon. A second click closes.
          if (Motion.PanelMotion.commitHover(root)) return
          if (trayItemRoot.reallyShown) root.close()
          else root.openSnip(trayItemRoot)
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
