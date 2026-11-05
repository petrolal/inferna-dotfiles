import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "../denon.bar/panels" as Motion
import QtQuick.Shapes

Item {
  id: root

  // Injected by inferna-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("INFERNA_PATH") || Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `inferna-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.hoverOpened = false
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
      root.hoverOpened = payload.hover === true && root.attached && root.opened
    }
  }

  // Opened by resting the pointer on the bottom frame (denon.shell's
  // MenuEdge): the menu tucks away again once the pointer leaves it, like
  // the rail's hover drawers. Typing or clicking inside pins it open.
  property bool hoverOpened: false

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  // Glass surfaces: the menu speaks the bar's sans instead of monospace;
  // nerd-font glyphs keep the monospace family via iconFamily.
  property string fontFamily: "Adwaita Sans"
  property string iconFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/inferna/inferna-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/inferna/extensions/inferna-menu.jsonc"
  // Menu title. Set "root": { "title": "YOUR NAME" } in the extension file above.
  readonly property string brandName: (root.item("root") && root.item("root").title) ? root.item("root").title : "INFERNA"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var sharedAppLibrary: root.shell ? root.shell.appLibrary : null
  readonly property var appLibrary: sharedAppLibrary || fallbackAppLibrary.item

  // Custom shell facades can omit the shared application library. Reuse the
  // standard implementation locally so entries, filtering and launching work.
  Loader {
    id: fallbackAppLibrary
    active: !root.sharedAppLibrary
    source: root.omarchyPath + "/shell/services/AppLibrary.qml"
  }

  onAppLibraryChanged: {
    if (root.appLibrary && root.providersLoaded["apps"]) root.mergeAppRows()
  }
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null; hoverOpened = false }
  // Bound to the central [menu] section in shell.toml via Commons.Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  // Pebble Shell: the menu rises out of the bottom frame as an attached
  // drawer (no scrim, no floating shadow, the shell's own surface, concave
  // necks into the frame), centred on the window area. Off for other bars.
  readonly property var shellBar: Motion.PanelMotion.bar && Motion.PanelMotion.bar.shellMode === true ? Motion.PanelMotion.bar : null
  readonly property bool attached: !!shellBar
  // Tide list (Pebble Shell only): Studio's card language — a big light
  // prompt, hairline icons, an accent bar + accent text for the selection,
  // nothing boxed. Top-level sections get Lucide line icons (icons/); deeper
  // rows keep their glyphs, drawn bare.
  readonly property bool tide: attached
  readonly property var lineIcons: ({ apps: 1, learn: 1, trigger: 1, style: 1, setup: 1, install: 1, remove: 1, update: 1, about: 1, system: 1, paper: 1 })
  // The theme accent, lifted for legibility as text on a dark surface.
  readonly property color tideAccent: Commons.Color.background.hslLightness < 0.5
    ? Qt.hsla(Commons.Color.accent.hslHue, Commons.Color.accent.hslSaturation, Math.max(Commons.Color.accent.hslLightness, 0.62), 1)
    : Commons.Color.accent
  readonly property color tideSurface: attached ? shellBar.shellSurface : background
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property color selectedBorder: Commons.Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.space(18)
  property int contentMargin: Style.space(8)
  property int headerHeight: tide && !dmenuActive ? Style.space(56) : Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  // Glass surfaces: key-hint footer under the list (hidden for dmenu prompts).
  readonly property bool showFooter: !root.dmenuActive
  readonly property int footerHeight: showFooter ? Style.space(30) : 0
  property int baseRowHeight: tide ? Style.space(44) : Math.max(Style.space(40), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.space(1)
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(320)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight + (footerHeight > 0 ? contentSpacing + footerHeight : 0), panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing - (root.footerHeight > 0 ? root.contentSpacing + root.footerHeight : 0)
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(inferna-font-current 2>/dev/null); inferna-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "inferna-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); inferna-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "inferna-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `inferna-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/inferna/extensions/inferna-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  PanelWindow {
    id: panel
    readonly property bool want: root.opened && root.rowsLoaded
    // Attached: the exact motion of the rail drawers (PanelHost) turned to
    // face up — the drawer pops out of the bottom frame edge, growing from
    // 82 % to full height off that edge and 94 % to full width about its
    // centre on a 420 ms OutBack (overshoot 1.25), fading in as it goes;
    // it tucks back in 150 ms. Interruptible: the Behavior retargets.
    property real reveal: want ? 1 : 0
    Behavior on reveal {
      enabled: root.attached
      NumberAnimation {
        duration: panel.want ? 420 : 150
        easing.type: panel.want ? Easing.OutBack : Easing.InCubic
        easing.overshoot: 1.25
      }
    }
    readonly property real popY: 0.82 + 0.18 * reveal
    readonly property real popX: 0.94 + 0.06 * reveal
    visible: root.attached ? (want || reveal > 0.001) : want
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "inferna-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: !root.attached || want ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Closing unfreezes both.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (visible && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onVisibleChanged: if (!visible) { cardTop = -1; maxRowsHeight = -1 }

    Rectangle {
      anchors.fill: parent
      color: root.attached ? "transparent" : root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    // Glass surfaces: soft analytic shadow under the frosted card.
    RectangularShadow {
      x: card.x; y: card.y + 8
      width: card.width; height: card.height
      radius: card.radius
      blur: 36
      spread: -6
      color: Qt.rgba(0, 0, 0, Commons.Color.background.hslLightness > 0.5 ? 0.16 : 0.4)
      opacity: card.opacity
      visible: card.visible && !root.attached
    }

    // Hover session: the card plus the frame strip beneath it.
    Item {
      id: hoverZone
      visible: root.attached
      x: card.x - Style.space(12)
      y: card.y - Style.space(12)
      width: card.width + Style.space(24)
      height: panel.height - y
      HoverHandler { id: zoneHover }
    }
    Timer {
      id: hoverLeaveTimer
      interval: 350
      running: root.hoverOpened && panel.want && !zoneHover.hovered
      onTriggered: if (root.hoverOpened && !zoneHover.hovered) Quickshell.execDetached(["inferna-menu", "close"])
    }

    // Attached: everything below lives in a stage that ends at the bottom
    // frame's inner edge, so the drawer slides up from behind the frame.
    Item {
      id: stage
      width: panel.width
      height: root.attached ? panel.height - root.shellBar.frameThickness : panel.height
      clip: root.attached

    Shape {
      id: drawerShape
      visible: root.attached
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      readonly property real x0: card.x
      readonly property real w: card.width
      opacity: root.attached ? Math.min(1, panel.reveal * 1.6) : 1
      transform: Scale {
        origin.x: card.x + card.width / 2; origin.y: stage.height
        xScale: root.attached ? panel.popX : 1; yScale: root.attached ? panel.popY : 1
      }
      readonly property real topY: card.y
      readonly property real bottomY: stage.height
      readonly property real r: Style.space(28)
      readonly property real n: Style.space(20)
      ShapePath {
        fillColor: root.attached ? root.shellBar.shellSurface : "transparent"
        strokeWidth: -1
        strokeColor: "transparent"
        startX: drawerShape.x0 - drawerShape.n; startY: drawerShape.bottomY
        PathArc { x: drawerShape.x0; y: drawerShape.bottomY - drawerShape.n; radiusX: drawerShape.n; radiusY: drawerShape.n; direction: PathArc.Counterclockwise }
        PathLine { x: drawerShape.x0; y: drawerShape.topY + drawerShape.r }
        PathArc { x: drawerShape.x0 + drawerShape.r; y: drawerShape.topY; radiusX: drawerShape.r; radiusY: drawerShape.r }
        PathLine { x: drawerShape.x0 + drawerShape.w - drawerShape.r; y: drawerShape.topY }
        PathArc { x: drawerShape.x0 + drawerShape.w; y: drawerShape.topY + drawerShape.r; radiusX: drawerShape.r; radiusY: drawerShape.r }
        PathLine { x: drawerShape.x0 + drawerShape.w; y: drawerShape.bottomY - drawerShape.n }
        PathArc { x: drawerShape.x0 + drawerShape.w + drawerShape.n; y: drawerShape.bottomY; radiusX: drawerShape.n; radiusY: drawerShape.n; direction: PathArc.Counterclockwise }
        PathLine { x: drawerShape.x0 - drawerShape.n; y: drawerShape.bottomY }
      }
    }

    BorderSurface {
      id: card
      readonly property real holeCenter: root.attached
        ? (root.shellBar.position === "right" ? root.shellBar.frameThickness + (panel.width - root.shellBar.railWidth - root.shellBar.frameThickness) / 2
                                              : root.shellBar.railWidth + (panel.width - root.shellBar.railWidth - root.shellBar.frameThickness) / 2)
        : panel.width / 2
      readonly property real fullHeight: root.attached
        ? Math.min(root.cardHeight + Style.space(8), Math.round(stage.height * 0.78))
        : Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      width: root.attached ? Math.max(root.cardWidth + Style.space(24), Math.min(Style.space(520), panel.width - Style.space(200))) : root.cardWidth
      height: fullHeight
      // Attached: submenus and search results resize the drawer smoothly
      // instead of snapping its top edge (only while it is fully out).
      Behavior on height {
        enabled: root.attached && panel.want && panel.reveal > 0.98
        NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
      }
      radius: root.attached ? Style.space(28) : root.cornerRadius
      x: Math.round(holeCenter - width / 2)
      y: root.attached ? stage.height - height : panel.effectiveCardTop
      transform: Scale {
        origin.x: card.width / 2; origin.y: card.height
        xScale: root.attached ? panel.popX : 1; yScale: root.attached ? panel.popY : 1
      }
      opacity: root.attached ? Math.max(0, Math.min(1, panel.reveal)) : 1
      color: root.attached ? "transparent" : root.background
      borderSpec: root.attached ? Border.none() : root.borderSpec
      padding: root.contentMargin + (root.attached ? Style.space(8) : 0)

      MouseArea { anchors.fill: parent; onPressed: root.hoverOpened = false; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          root.hoverOpened = false
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Column {
        // Attached: the rows fade and drift up a touch behind the surface.
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            id: searchGlyph
            visible: (!root.dmenuActive || root.mode !== "input") && !(root.tide && !root.dmenuActive)
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf002"
            color: root.foreground
            opacity: 0.45
            font.family: root.iconFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: headerBadge
            visible: !root.dmenuActive && !root.tide
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.activeMenu === "root" ? root.brandName : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "")).toUpperCase()
            color: Commons.Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Bold
            font.letterSpacing: 1.2
          }

          Text {
            id: promptText
            readonly property bool tideHeader: root.tide && !root.dmenuActive
            readonly property string menuTitle: root.activeMenu === "root" ? root.brandName : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "")).replace(/…$/, "")
            textFormat: Text.PlainText
            anchors.left: searchGlyph.visible ? searchGlyph.right : parent.left
            anchors.right: headerBadge.visible ? headerBadge.left : parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…")
              : tideHeader ? (root.activeMenu === "root" ? "What do you need?" : menuTitle)
              : ("Search " + menuTitle + "…"))
            anchors.leftMargin: tideHeader ? Style.space(4) : Style.space(10)
            anchors.rightMargin: Style.space(tideHeader ? 24 : 10)
            color: root.foreground
            opacity: root.filterText ? 1 : (tideHeader ? 0.92 : 0.5)
            font.family: root.fontFamily
            font.pixelSize: tideHeader ? Style.space(30) : Style.font.title
            font.weight: tideHeader ? Font.ExtraLight : Font.Normal
            font.letterSpacing: tideHeader ? -0.5 : 0
            elide: Text.ElideRight
          }

          // Tide: an accent caret after the prompt, blinking while open.
          Rectangle {
            visible: promptText.tideHeader && panel.want
            x: promptText.x + Math.min(promptText.contentWidth, promptText.width) + Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: Style.space(28)
            radius: 1
            color: root.tideAccent
            SequentialAnimation on opacity {
              running: promptText.tideHeader && panel.want
              loops: Animation.Infinite
              NumberAnimation { to: 1; duration: 80 }
              PauseAnimation { duration: 560 }
              NumberAnimation { to: 0; duration: 220; easing.type: Easing.InOutSine }
              PauseAnimation { duration: 280 }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.tide ? Style.space(4) : 0
            anchors.rightMargin: root.tide ? Style.space(4) : 0
            height: 1
            color: Util.alpha(root.foreground, root.tide ? 0.12 : 0.08)
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              readonly property bool lineIcon: root.tide && !row.isApp && root.lineIcons[row.itemId] === 1
              readonly property real iconLeft: root.tide ? Style.space(12) : root.rowReservedBorderLeft + Style.space(6)

              radius: Style.space(10)
              color: root.tide ? "transparent" : (row.hasCursor ? root.selectedBackground : "transparent")
              borderSpec: root.tide ? Border.none() : (row.hasCursor ? root.selectedBorderSpec : Border.none())

              // Tide: the selection is a short accent bar that grows in.
              Rectangle {
                visible: root.tide
                width: 3
                height: row.hasCursor ? Style.space(20) : 0
                radius: 1.5
                color: root.tideAccent
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] } }
              }

              // Glass: each icon sits in a small tile; the selected row lifts
              // its tile and glyph into the theme accent.
              Rectangle {
                visible: row.hasIcon && !root.tide
                width: Style.space(28)
                height: width
                radius: Style.space(8)
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(6)
                anchors.verticalCenter: iconText.verticalCenter
                color: row.hasCursor
                  ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)
                  : Util.alpha(root.foreground, 0.05)
              }

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp && !row.lineIcon
                text: row.icon
                color: row.hasCursor ? (root.tide ? root.tideAccent : Commons.Color.accent) : Util.alpha(root.foreground, root.tide ? 0.7 : 0.75)
                font.family: row.iconFont.length > 0 ? row.iconFont : root.iconFamily
                font.pixelSize: root.tide ? Style.font.icon - 1 : Style.font.icon
                width: Style.space(root.tide ? 22 : 28)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: row.iconLeft
                Behavior on color { ColorAnimation { duration: 140 } }
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              // Tide: Lucide hairline icon for top-level sections, tinted.
              Image {
                id: lineIconImage
                visible: false
                source: row.lineIcon ? Qt.resolvedUrl("icons/" + row.itemId + ".svg") : ""
                width: Style.space(18)
                height: width
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
              }
              MultiEffect {
                visible: row.lineIcon
                source: lineIconImage
                width: lineIconImage.width
                height: lineIconImage.height
                x: iconText.x + (iconText.width - width) / 2
                y: iconText.y + (iconText.height - height) / 2
                colorization: 1
                colorizationColor: row.hasCursor ? root.tideAccent : root.foreground
                opacity: row.hasCursor ? 1 : 0.7
                Behavior on colorizationColor { ColorAnimation { duration: 140 } }
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: Style.font.iconLarge - 2
                height: Style.font.iconLarge - 2
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: row.iconLeft + (iconText.width - width) / 2
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(root.tide ? 14 : 12) : root.rowReservedBorderLeft + Style.space(14)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: root.tide ? (row.hasCursor ? root.tideAccent : root.foreground) : (row.hasCursor ? root.selectedText : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: root.tide ? Style.space(16) : Style.font.subtitle + 1
                  font.weight: root.tide ? (row.hasCursor ? Font.Medium : Font.Normal) : (row.hasCursor ? Font.DemiBold : Font.Medium)
                  Behavior on color { enabled: root.tide; ColorAnimation { duration: 140 } }
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                  color: row.hasCursor ? (root.tide ? root.tideAccent : Commons.Color.accent) : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" ? (row.hasCursor ? 0.9 : (root.tide ? 0.4 : 0.3)) : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.tideSurface }
              GradientStop { position: 1; color: Util.alpha(root.tideSurface, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.tideSurface, 0) }
              GradientStop { position: 1; color: root.tideSurface }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Text {
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              textFormat: Text.PlainText
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          visible: root.showFooter
          width: parent.width
          height: root.footerHeight

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Util.alpha(root.foreground, root.tide ? 0.12 : 0.08)
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Style.space(2)
            spacing: Style.space(14)

            Repeater {
              model: root.activeMenu === "root"
                ? [["↑↓", root.tide ? "navigate" : "Navigate"], ["↵", root.tide ? "open" : "Open"], ["esc", root.tide ? "close" : "Close"]]
                : [["↑↓", root.tide ? "navigate" : "Navigate"], ["↵", root.tide ? "open" : "Open"], ["←", root.tide ? "back" : "Back"], ["esc", root.tide ? "close" : "Close"]]

              Row {
                required property var modelData
                spacing: Style.space(5)

                Rectangle {
                  width: keyText.implicitWidth + Style.space(10)
                  height: keyText.implicitHeight + Style.space(2)
                  radius: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  color: Util.alpha(root.foreground, 0.07)

                  Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: modelData[0]
                    color: root.foreground
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData[1]
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }
    }
    }  // stage
  }
}
