import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "inferna.indicators"

  readonly property var defaultIndicatorEntries: [ "Dictation", "ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake" ]
  readonly property var indicatorEntries: indicatorEntriesFromSettings(settings)
  property var activeIndicatorIds: []
  property var indicatorActiveStates: ({})
  property bool indicatorAreaHovered: false
  property bool indicatorItemHovered: false
  readonly property bool alwaysShowIndicators: setting("alwaysShow", false) === true
  readonly property bool revealInactiveIndicators: alwaysShowIndicators || indicatorAreaHovered || indicatorItemHovered || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)

  signal refreshRequested()

  ListModel { id: activeIndicatorModel }

  function entryId(entry) {
    if (typeof entry === "string") return entry
    if (Util.isPlainObject(entry)) {
      var id = entry["id"]
      if (id !== undefined && id !== null && String(id) !== "") return String(id)
    }
    return ""
  }

  function entrySettings(entry) {
    if (!Util.isPlainObject(entry)) return {}
    var copy = {}
    for (var key in entry) {
      if (key === "id") continue
      copy[key] = entry[key]
    }
    return copy
  }

  function indicatorEntriesFromSettings(settings) {
    var source = defaultIndicatorEntries
    if (settings.items && typeof settings.items.length === "number" && settings.items.length > 0) source = settings.items
    else if (settings.indicators && typeof settings.indicators.length === "number" && settings.indicators.length > 0) source = settings.indicators

    var result = []
    for (var i = 0; i < source.length; i++) {
      var item = source[i]
      if (typeof item !== "string" && item !== null && typeof item === "object") {
        try {
          item = JSON.parse(JSON.stringify(item))
        } catch (error) {
        }
      }
      var id = entryId(item)
      if (id !== "") result.push(item)
    }
    return result
  }

  function setIndicatorAreaHovered(hovered) {
    indicatorAreaHovered = hovered
    if (hovered) indicatorHideTimer.stop()
    else indicatorHideTimer.restart()
  }

  function setIndicatorItemHovered(hovered) {
    if (hovered) {
      indicatorItemHovered = true
      indicatorHideTimer.stop()
    } else {
      indicatorHideTimer.restart()
    }
  }

  function hasIndicatorId(id) {
    for (var i = 0; i < indicatorEntries.length; i++) {
      if (entryId(indicatorEntries[i]) === id) return true
    }
    return false
  }

  function entryForId(id) {
    for (var i = 0; i < indicatorEntries.length; i++) {
      var entry = indicatorEntries[i]
      if (entryId(entry) === id) return entry
    }

    return { id: id }
  }

  function activeModelIndex(id) {
    for (var i = 0; i < activeIndicatorModel.count; i++) {
      if (activeIndicatorModel.get(i).activeId === id) return i
    }
    return -1
  }

  function copyActiveStates() {
    var states = {}
    for (var id in indicatorActiveStates) {
      if (indicatorActiveStates[id] === true) states[id] = true
    }
    return states
  }

  function orderedActiveIds(states, preferredOrder) {
    var ids = []

    for (var i = 0; i < preferredOrder.length; i++) {
      var id = preferredOrder[i]
      if (ids.indexOf(id) === -1 && hasIndicatorId(id) && states[id] === true) ids.push(id)
    }

    return ids
  }

  function syncActiveIndicatorModel() {
    for (var i = activeIndicatorModel.count - 1; i >= 0; i--) {
      if (activeIndicatorIds.indexOf(activeIndicatorModel.get(i).activeId) === -1)
        activeIndicatorModel.remove(i)
    }

    for (var j = 0; j < activeIndicatorIds.length; j++) {
      var id = activeIndicatorIds[j]
      var index = activeModelIndex(id)
      if (index === -1) activeIndicatorModel.insert(j, { activeId: id })
      else if (index !== j) activeIndicatorModel.move(index, j, 1)
    }
  }

  function setIndicatorActive(entry, active) {
    var id = entryId(entry)
    if (id === "") return

    var states = copyActiveStates()
    if (active) states[id] = true
    else delete states[id]

    indicatorActiveStates = states

    var ids = orderedActiveIds(states, activeIndicatorIds)
    // The active block sits closest to the clock, so newcomers go on the far
    // side of it. Appending would shove everything already showing sideways.
    if (active && ids.indexOf(id) === -1 && hasIndicatorId(id)) ids.unshift(id)
    activeIndicatorIds = ids
    syncActiveIndicatorModel()
  }

  function syncActiveIndicatorOrder() {
    activeIndicatorIds = orderedActiveIds(indicatorActiveStates, activeIndicatorIds)
    syncActiveIndicatorModel()
  }

  function refresh() { root.refreshRequested() }

  onIndicatorEntriesChanged: syncActiveIndicatorOrder()

  // Only the tree for the current orientation exists (see orientationLoader
  // below); its wrapper keeps the stock sizing expressions, so the root's
  // implicit size still follows the blocks synchronously rather than waiting
  // on a positioner's polish.
  implicitWidth: orientationLoader.item ? orientationLoader.item.implicitWidth : 0
  implicitHeight: orientationLoader.item ? orientationLoader.item.implicitHeight : 0

  IpcHandler {
    target: "inferna.indicators"

    function refresh(): void {
      root.broadcast("refresh")
    }
  }

  Timer {
    id: indicatorHideTimer
    interval: 120
    onTriggered: {
      if (!root.indicatorAreaHovered)
        root.indicatorItemHovered = false
    }
  }

  Component.onCompleted: root.refreshRequested()

  // Instantiating both orientation trees and toggling `visible` doubled every
  // indicator per bar (and every process an indicator spawns, once per
  // monitor). Load only the tree that matches the bar orientation instead.
  Loader {
    id: orientationLoader
    sourceComponent: root.vertical ? verticalIndicatorsTree : horizontalIndicatorsTree
  }

  Component {
    id: horizontalIndicatorsTree

    Item {
      implicitWidth: activeHorizontalBlock.implicitWidth + inactiveHorizontalArea.implicitWidth
      implicitHeight: Math.max(activeHorizontalBlock.implicitHeight, inactiveHorizontalArea.implicitHeight)
      width: implicitWidth
      height: implicitHeight

      Row {
        id: horizontalIndicators

        spacing: 0

        HoverHandler {
          onHoveredChanged: root.setIndicatorAreaHovered(hovered)
        }

        Item {
          id: inactiveHorizontalArea

          implicitWidth: root.revealInactiveIndicators ? inactiveHorizontalBlock.implicitWidth : 0
          // Animate the layout's source width so icons, clock, and glass move together.
          Behavior on implicitWidth {
            NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
          }
          implicitHeight: Math.max(inactiveHorizontalBlock.implicitHeight, root.barSize)
          width: implicitWidth
          height: implicitHeight
          clip: true

          IndicatorBlock {
            id: inactiveHorizontalBlock
            anchors.verticalCenter: parent.verticalCenter
            indicatorsModule: root
            indicatorEntries: root.indicatorEntries
            indicatorBlock: "inactive"
            horizontal: true
            reportActiveState: !root.vertical
          }

          HoverHandler {
            onHoveredChanged: root.setIndicatorAreaHovered(hovered)
          }
        }

        ActiveIndicatorBlock {
          id: activeHorizontalBlock
          indicatorsModule: root
          indicatorModel: activeIndicatorModel
          horizontal: true
          reportActiveState: !root.vertical
        }
      }
    }
  }

  Component {
    id: verticalIndicatorsTree

    Item {
      implicitWidth: Math.max(activeVerticalBlock.implicitWidth, inactiveVerticalArea.implicitWidth)
      implicitHeight: activeVerticalBlock.implicitHeight + inactiveVerticalArea.implicitHeight
      width: implicitWidth
      height: implicitHeight

      Column {
        id: verticalIndicators

        spacing: 0

        HoverHandler {
          onHoveredChanged: root.setIndicatorAreaHovered(hovered)
        }

        Item {
          id: inactiveVerticalArea

          implicitWidth: Math.max(inactiveVerticalBlock.implicitWidth, root.barSize)
          implicitHeight: root.revealInactiveIndicators ? inactiveVerticalBlock.implicitHeight : 0
          Behavior on implicitHeight {
            NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
          }
          width: implicitWidth
          height: implicitHeight
          clip: true

          IndicatorBlock {
            id: inactiveVerticalBlock
            anchors.horizontalCenter: parent.horizontalCenter
            indicatorsModule: root
            indicatorEntries: root.indicatorEntries
            indicatorBlock: "inactive"
            horizontal: false
            reportActiveState: root.vertical
          }

          HoverHandler {
            onHoveredChanged: root.setIndicatorAreaHovered(hovered)
          }
        }

        ActiveIndicatorBlock {
          id: activeVerticalBlock
          indicatorsModule: root
          indicatorModel: activeIndicatorModel
          horizontal: false
          reportActiveState: root.vertical
        }
      }
    }
  }

  HoverHandler {
    onHoveredChanged: root.setIndicatorAreaHovered(hovered)
  }

  component ActiveIndicatorBlock: Item {
    id: activeIndicatorBlockRoot

    property var indicatorModel: null
    property var indicatorsModule: null
    property bool horizontal: true
    property bool reportActiveState: false

    implicitWidth: blockLoader.item ? blockLoader.item.implicitWidth : 0
    implicitHeight: blockLoader.item ? blockLoader.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: blockLoader

      anchors.centerIn: parent
      sourceComponent: activeIndicatorBlockRoot.horizontal ? horizontalActiveIndicatorBlock : verticalActiveIndicatorBlock
    }

    Component {
      id: horizontalActiveIndicatorBlock

      Row {
        spacing: 0

        Repeater {
          model: activeIndicatorBlockRoot.indicatorModel

          IndicatorLoader {
            required property string activeId
            indicatorsModule: activeIndicatorBlockRoot.indicatorsModule
            entry: activeIndicatorBlockRoot.indicatorsModule.entryForId(activeId)
            indicatorBlock: "active"
            reportActiveState: activeIndicatorBlockRoot.reportActiveState
          }
        }
      }
    }

    Component {
      id: verticalActiveIndicatorBlock

      Column {
        spacing: 0

        Repeater {
          model: activeIndicatorBlockRoot.indicatorModel

          IndicatorLoader {
            required property string activeId
            indicatorsModule: activeIndicatorBlockRoot.indicatorsModule
            entry: activeIndicatorBlockRoot.indicatorsModule.entryForId(activeId)
            indicatorBlock: "active"
            reportActiveState: activeIndicatorBlockRoot.reportActiveState
          }
        }
      }
    }
  }

  component IndicatorBlock: Item {
    id: indicatorBlockRoot

    property var indicatorEntries: []
    property var indicatorsModule: null
    property string indicatorBlock: "active"
    property bool horizontal: true
    property bool reportActiveState: false

    implicitWidth: blockLoader.item ? blockLoader.item.implicitWidth : 0
    implicitHeight: blockLoader.item ? blockLoader.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: blockLoader

      anchors.centerIn: parent
      sourceComponent: indicatorBlockRoot.horizontal ? horizontalIndicatorBlock : verticalIndicatorBlock
    }

    Component {
      id: horizontalIndicatorBlock

      Row {
        spacing: 0

        Repeater {
          model: indicatorBlockRoot.indicatorEntries

          IndicatorLoader {
            required property var modelData
            indicatorsModule: indicatorBlockRoot.indicatorsModule
            entry: modelData
            indicatorBlock: indicatorBlockRoot.indicatorBlock
            reportActiveState: indicatorBlockRoot.reportActiveState
          }
        }
      }
    }

    Component {
      id: verticalIndicatorBlock

      Column {
        spacing: 0

        Repeater {
          model: indicatorBlockRoot.indicatorEntries

          IndicatorLoader {
            required property var modelData
            indicatorsModule: indicatorBlockRoot.indicatorsModule
            entry: modelData
            indicatorBlock: indicatorBlockRoot.indicatorBlock
            reportActiveState: indicatorBlockRoot.reportActiveState
          }
        }
      }
    }
  }

  component IndicatorLoader: Item {
    id: indicatorSlot

    required property var entry
    property var indicatorsModule: null
    required property string indicatorBlock
    property bool reportActiveState: false
    property bool activeStateObserved: false
    readonly property string indicatorId: root.entryId(entry)
    readonly property var indicatorSettings: root.entrySettings(entry)
    readonly property var barRef: root.bar

    implicitWidth: indicatorSource.item && indicatorSource.item.visible ? indicatorSource.item.implicitWidth : 0
    implicitHeight: indicatorSource.item && indicatorSource.item.visible ? indicatorSource.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    onEntryChanged: {
      activeStateObserved = false
      injectProps()
      syncActiveState()
    }
    onIndicatorBlockChanged: injectProps()
    onIndicatorSettingsChanged: injectProps()
    onIndicatorsModuleChanged: {
      injectProps()
      syncActiveState()
    }
    onReportActiveStateChanged: syncActiveState()
    onBarRefChanged: injectProps()

    HoverHandler {
      id: indicatorHover
      onHoveredChanged: indicatorSlot.syncEmphasis()
    }
    // Hovered icon sits above its neighbours while it is enlarged.
    z: indicatorHover.hovered ? 1 : 0

    // Revealed-but-idle icons are drawn at 45% by the stock BarIndicator; lift them so
    // they read as clickable, and make the hovered one fully solid. Opacity is only set
    // when the reveal/hover state changes (never from opacityChanged), so the stock
    // fade animation still runs and hiding still works.
    readonly property real revealedOpacity: 0.72
    function syncEmphasis() {
      var item = indicatorSource.item
      if (!item || item.belongsInBlock === undefined) return
      var shown = item.belongsInBlock && (item.effectiveActive || item.inactiveRevealed)
      if (shown && indicatorHover.hovered) item.opacity = 1
      else if (shown && !item.effectiveActive) item.opacity = revealedOpacity
      else if (item.syncIndicatorOpacity) item.syncIndicatorOpacity()
    }
    Connections {
      target: indicatorSource.item
      ignoreUnknownSignals: true
      // Run after the stock handlers have applied their own value.
      function onInactiveRevealedChanged() { Qt.callLater(indicatorSlot.syncEmphasis) }
      function onEffectiveActiveChanged() { Qt.callLater(indicatorSlot.syncEmphasis) }
      function onBelongsInBlockChanged() { Qt.callLater(indicatorSlot.syncEmphasis) }
    }

    Rectangle {
      anchors.centerIn: parent
      // The hover pad grows a little with the icon but stays inside the pill.
      readonly property real grow: 1 + (indicatorSource.scale - 1) * 0.4
      width: Math.max(0, parent.width - 2) * grow
      height: Math.min(24, parent.height) * grow
      radius: 6
      color: root.bar ? Qt.rgba(root.bar.barForeground.r, root.bar.barForeground.g, root.bar.barForeground.b, 0.15) : "#24ffffff"
      opacity: indicatorHover.hovered && indicatorSource.item && indicatorSource.item.visible ? 1 : 0
      scale: opacity > 0 ? 1 : 0.86

      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    Loader {
      id: indicatorSource

      anchors.fill: parent
      // Expand the icon under the pointer so it is easy to see and hit.
      scale: indicatorHover.hovered && item && item.visible && item.interactive ? 1.4 : 1
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
      source: indicatorSlot.indicatorId ? Qt.resolvedUrl("indicators/" + indicatorSlot.indicatorId + ".qml") : ""
      onLoaded: {
        indicatorSlot.injectProps()
        indicatorSlot.syncActiveState()
        Qt.callLater(indicatorSlot.syncEmphasis)
      }
      onStatusChanged: if (status === Loader.Error) console.warn("Indicator loader error", indicatorSlot.indicatorId, source)
    }

    Connections {
      target: indicatorSource.item
      ignoreUnknownSignals: true
      function onActiveChanged() { indicatorSlot.syncActiveState() }
    }

    function injectProps() {
      var target = indicatorSource.item
      if (!target) return
      if ("bar" in target) target.bar = root.bar
      if ("moduleName" in target) target.moduleName = indicatorId
      if ("settings" in target) target.settings = indicatorSettings
      if ("indicatorBlock" in target) target.indicatorBlock = indicatorBlock
      if ("indicatorHost" in target) target.indicatorHost = root
      if ("activeOverride" in target) target.activeOverride = indicatorBlock === "active" ? true : null
    }

    function syncActiveState() {
      if (!reportActiveState || !indicatorsModule || !indicatorsModule.setIndicatorActive) return

      var active = !!indicatorSource.item && indicatorSource.item.active === true
      if (indicatorBlock === "active") {
        if (active) activeStateObserved = true
        else if (!activeStateObserved) return
      }

      indicatorsModule.setIndicatorActive(entry, active)
    }
  }
}
