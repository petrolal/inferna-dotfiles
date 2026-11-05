import "../denon.bar/panels" as Motion
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Commons.Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Commons.Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("inferna-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    var reset = new Date(String(resetAt || "")).getTime()
    var expired = isFinite(reset) && reset <= root.nowMs
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: expired ? 0 : Number(percent),
      resetAt: expired ? "" : String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- fuel gauges
  //
  // The panel leads with what is LEFT, not what is used: every agent shows its
  // weekly allowance as a big "% left" with a bar that starts full on the left
  // and gives way from the right as the window is spent.
  property bool showHistory: false
  property string historyProviderId: ""
  readonly property var historyProvider: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === historyProviderId) return providers[i]
    return providers.length > 0 ? providers[0] : null
  }

  function fuelWindows(p) {
    var all = limitWindows(p)
    var weekly = null, session = null, extras = []
    for (var i = 0; i < all.length; i++) {
      var w = all[i]
      if (!weekly && w.title === "Weekly") weekly = w
      else if (!session && w.title === "Session") session = w
      else extras.push(w)
    }
    var main = []
    if (weekly) main.push({ window: weekly, label: "Weekly", big: true })
    if (session) main.push({ window: session, label: "5-hour window", big: !weekly })
    for (var j = 0; j < extras.length && main.length === 0; j++) main.push({ window: extras[j], label: extras[j].title, big: true })
    return { main: main, extras: main.length ? extras.filter(function(e) { return main.every(function(m) { return m.window !== e }) }) : [],
             weeklyOnly: !!weekly && !session }
  }

  function leftOf(w) { return w && w.percent >= 0 ? clamp(1 - w.percent, 0, 1) : -1 }

  // Healthy in the theme accent, warming toward the theme's urgent colour as
  // the tank runs low.
  function fuelColor(left) {
    var a = Commons.Color.accent, u = root.urgent
    if (left >= 0.5) return a
    if (left <= 0.2) return u
    var t = (0.5 - left) / 0.3
    return Qt.rgba(a.r + (u.r - a.r) * t, a.g + (u.g - a.g) * t, a.b + (u.b - a.b) * t, 1)
  }

  function resetLine(w) {
    var ms = resetMsFor(w)
    if (ms <= 0) return ""
    var when = new Date(root.nowMs + ms)
    var sameDay = new Date(root.nowMs).toDateString() === when.toDateString()
    return "Resets " + (ms > 24 * 3600 * 1000 ? Qt.formatDateTime(when, "ddd h:mm AP") + " · " : (sameDay ? "" : "tomorrow · "))
      + "in " + formatDuration(ms)
  }

  function updatedAgo() {
    var newest = 0
    for (var i = 0; i < providers.length; i++) {
      var t = new Date(String(providers[i].updatedAt || "")).getTime()
      if (isFinite(t)) newest = Math.max(newest, t)
    }
    if (!newest) return ""
    var mins = Math.floor((root.nowMs - newest) / 60000)
    return mins < 1 ? "Updated just now" : "Updated " + formatDuration(mins * 60000) + " ago"
  }

  function todayTokens(p) {
    if (!p) return 0
    if (p.todayTotalTokens !== undefined) return Number(p.todayTotalTokens || 0)
    var days = p.recentDays || []
    for (var i = 0; i < days.length; i++)
      if (String(days[i].date) === todayDate()) return Number(days[i].messageCount || 0)
    return 0
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  // Banked resets (Codex "Full reset" credits, Claude "Free limit reset" grants): count + soonest expiry.
  function resetCredits(p) {
    var r = p ? p.resetCredits : null
    return r && Number(r.available || 0) > 0 ? r : null
  }

  function resetCreditsLine(r) {
    if (!r) return ""
    var n = Number(r.available || 0)
    var line = n + (n === 1 ? " banked reset" : " banked resets")
    var soonest = 0
    var list = r.credits || []
    for (var i = 0; i < list.length; i++) {
      var e = Number(list[i].expiresAt || 0)
      if (e > 0 && (soonest === 0 || e < soonest)) soonest = e
    }
    if (soonest > 0) {
      var d = new Date(soonest * 1000)
      line += " · expires " + d.toLocaleDateString(Qt.locale(), "MMM d")
    }
    return line
  }

  function resetCreditsTooltip(r) {
    if (!r) return ""
    var c = (r.credits || [])[0]
    var bits = []
    if (c && c.description) bits.push(c.description)
    bits.push("Click, then confirm.")
    return bits.join("\n")
  }

  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Commons.Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
    function history(): string { root.showHistory = !root.showHistory; return root.showHistory ? "shown" : "hidden" }
  }

  // The bar slot is the fuel gauge itself: the Claude Code and Codex marks,
  // each followed by the share of its binding window still unspent, counting
  // down from 100%. The panel below is the same data in full. Other agents
  // (Fireworks) stay in the panel only.
  readonly property var gaugeIds: ["claude", "codex"]
  readonly property var gaugeProviders: {
    var out = []
    for (var i = 0; i < gaugeIds.length; i++)
      for (var k = 0; k < providers.length; k++)
        if (providers[k].providerId === gaugeIds[i]) { out.push(providers[k]); break }
    return out
  }

  function gaugeTooltip() {
    var bits = []
    for (var i = 0; i < gaugeProviders.length; i++) {
      var p = gaugeProviders[i]
      var w = bindingWindow(p)
      var left = leftOf(w)
      var line = p.name || p.providerId
      if (left < 0) line += ": no usage data"
      else {
        line += " " + Math.round(left * 100) + "% left"
        var reset = resetLine(w)
        if (reset !== "") line += " · " + reset.charAt(0).toLowerCase() + reset.slice(1)
      }
      bits.push(line)
    }
    return bits.join("    ")
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.gaugeProviders.length === 0 ? "󱚣" : ""
    labelVisible: root.gaugeProviders.length === 0
    hasVisualContent: true
    fontSize: Style.bar.iconFont
    // On a vertical bar (the Pebble Shell rail) the gauges stack: mark over
    // number, one agent under the other, at the rail's own width.
    fixedWidth: button.vertical ? -1 : root.gaugeProviders.length === 0 ? Style.bar.iconSlot : gauges.implicitWidth + Style.space(20)
    fixedHeight: button.vertical && root.gaugeProviders.length > 0 ? gauges.implicitHeight + Style.space(16) : -1
    active: root.alarming
    tooltipText: root.gaugeTooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
      else if (!Motion.PanelMotion.commitHover(root)) root.toggle()
    }

    // One mark and one number. The mark is tinted with the bar foreground so
    // both agents follow the theme; the number turns the bar's urgent colour
    // once a fifth of the window is left.
    component BarGauge: Grid {
      id: gauge
      property var agent: null
      readonly property real leftShare: root.leftOf(root.bindingWindow(agent))
      readonly property real markSize: Style.space(14)
      // Pebble Shell rail: a ring that empties as the window is spent, the
      // number inside (Paper "Fan" iteration). Mark and label give way to it.
      readonly property bool ring: button.vertical && Motion.PanelMotion.tide
      readonly property color ringColor: leftShare >= 0 && leftShare <= 0.2 ? button.activeColor
        : (agent && agent.providerId === "claude") ? Commons.Color.accent : button.foreground

      Item {
        visible: gauge.ring
        width: Style.space(31); height: width
        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.14)
            strokeWidth: Style.space(2.5); fillColor: "transparent"
            PathAngleArc { centerX: Style.space(15.5); centerY: Style.space(15.5); radiusX: Style.space(13); radiusY: Style.space(13); startAngle: 0; sweepAngle: 360 }
          }
          ShapePath {
            strokeColor: gauge.ringColor
            strokeWidth: Style.space(2.5); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: Style.space(15.5); centerY: Style.space(15.5); radiusX: Style.space(13); radiusY: Style.space(13); startAngle: -90; sweepAngle: 360 * Math.max(0, gauge.leftShare) }
          }
        }
        Text {
          anchors.centerIn: parent
          text: gauge.leftShare < 0 ? "\u2013" : Math.round(gauge.leftShare * 100)
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.space(10)
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
        }
      }
      columns: button.vertical ? 1 : 2
      rowSpacing: Style.space(3)
      columnSpacing: Style.space(5)
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      Item {
        visible: !gauge.ring
        width: gauge.markSize
        height: gauge.markSize
        Image {
          id: markImage
          anchors.fill: parent
          source: gauge.agent ? Qt.resolvedUrl("assets/" + gauge.agent.providerId + ".svg") : ""
          fillMode: Image.PreserveAspectFit
          sourceSize.width: 64
          sourceSize.height: 64
          visible: false
          layer.enabled: true
        }
        MultiEffect {
          anchors.fill: markImage
          source: markImage
          colorization: 1
          colorizationColor: button.foreground
        }
      }

      Text {
        visible: !gauge.ring
        text: gauge.leftShare < 0 ? "\u2013" : Math.round(gauge.leftShare * 100) + (button.vertical ? "" : "%")
        textFormat: Text.PlainText
        color: gauge.leftShare >= 0 && gauge.leftShare <= 0.2 ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: 160 } }
      }
    }

    Grid {
      id: gauges
      anchors.centerIn: parent
      columns: button.vertical ? 1 : Math.max(1, root.gaugeProviders.length)
      rowSpacing: Style.space(10)
      columnSpacing: Style.space(12)
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter
      visible: root.gaugeProviders.length > 0
      Repeater {
        model: root.gaugeProviders
        delegate: BarGauge {
          required property var modelData
          agent: modelData
        }
      }
    }
  }

  Motion.PopupPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(14)
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && root.showHistory) {
          var i = 0
          for (var k = 0; k < root.providers.length; k++) if (root.historyProvider && root.providers[k].providerId === root.historyProvider.providerId) i = k
          var n = root.providers.length
          if (n) root.historyProviderId = root.providers[((i + dx) % n + n) % n].providerId
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "h" || t === "H") root.showHistory = !root.showHistory
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Header ----------
          Item {
            width: parent.width
            height: Style.space(26)
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              text: "Usage limits"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Motion.PanelMotion.tide ? Style.space(20) : Style.font.title + 1
              font.weight: Motion.PanelMotion.tide ? Font.Light : Font.DemiBold
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: usage.refreshing ? "Refreshing…" : root.updatedAgo()
                color: root.alpha(root.foreground, 0.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption + 1
              }
              Rectangle {
                width: Style.space(26); height: width; radius: Style.space(8)
                color: refreshMouse.containsMouse ? root.alpha(root.foreground, 0.1) : root.alpha(root.foreground, 0.05)
                Text {
                  anchors.centerIn: parent
                  text: "󰑓"
                  color: root.alpha(root.foreground, 0.75)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  RotationAnimation on rotation { running: usage.refreshing; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                }
                MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refreshNow() }
                PanelToolTip { visible: refreshMouse.containsMouse; text: "Refresh (R)"; fontFamily: root.fontFamily }
              }
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- One fuel card per agent ----------
          Repeater {
            model: root.providers
            AgentCard {
              required property var modelData
              width: column.width
              agent: modelData
            }
          }

          // ---------- Footer: today + token history ----------
          Item {
            visible: root.providers.length > 0
            width: parent.width
            height: Style.space(30)
            Rectangle { width: parent.width; height: 1; color: root.alpha(root.foreground, 0.08) }
            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.bottom: parent.bottom
              spacing: Style.space(14)
              Repeater {
                model: root.providers
                Row {
                  required property var modelData
                  required property int index
                  spacing: Style.space(6)
                  Rectangle {
                    width: Style.space(6); height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: index === 0 ? Commons.Color.accent : root.alpha(root.foreground, 0.55)
                  }
                  Text {
                    text: usage.formatTokenCount(root.todayTokens(modelData)) + " today"
                    color: root.alpha(root.foreground, 0.72)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall + 1
                    font.weight: Font.Medium
                  }
                }
              }
            }
            Row {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              spacing: Style.space(4)
              Text {
                text: "Token history"
                color: historyMouse.containsMouse || root.showHistory ? root.foreground : root.alpha(root.foreground, 0.72)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall + 1
                font.weight: Font.Medium
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.showHistory ? "󰅀" : "󰅂"
                color: root.alpha(root.foreground, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
            MouseArea {
              id: historyMouse
              anchors.right: parent.right
              anchors.top: parent.top; anchors.bottom: parent.bottom
              width: Style.space(120)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showHistory = !root.showHistory
            }
          }

          // ---------- Token history (secondary, collapsed by default) ----------
          Column {
            id: history
            visible: root.showHistory && !!root.historyProvider
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.historyProvider ? (root.historyProvider.recentDays || []) : []
            readonly property real peak: Math.max(1, root.weekPeak(root.historyProvider))
            readonly property var models: root.modelRows(root.historyProvider)

            Motion.GlassTrack {
              visible: root.providers.length > 1
              width: parent.width
              foreground: root.foreground
              Row {
                width: parent.width
                spacing: Style.space(2)
                Repeater {
                  model: root.providers
                  Rectangle {
                    required property var modelData
                    readonly property bool on: !!root.historyProvider && root.historyProvider.providerId === modelData.providerId
                    width: (parent.width - Style.space(2) * (root.providers.length - 1)) / root.providers.length
                    height: Style.space(26)
                    radius: Style.space(8)
                    color: on ? root.alpha(root.foreground, 0.14) : "transparent"
                    Text {
                      anchors.centerIn: parent
                      text: modelData.providerName
                      color: parent.on ? root.foreground : root.alpha(root.foreground, 0.55)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall + 1
                      font.weight: parent.on ? Font.DemiBold : Font.Medium
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.historyProviderId = modelData.providerId }
                  }
                }
              }
            }

            Motion.GlassSection { width: parent.width; text: "TOKENS BY DAY"; foreground: root.foreground; fontFamily: root.fontFamily }
            Repeater {
              model: history.days
              DayRow {
                required property var modelData
                width: history.width
                day: modelData
                ratio: Number(modelData.messageCount || 0) / history.peak
                today: String(modelData.date || "") === root.todayDate()
              }
            }

            Motion.GlassSection { visible: history.models.length > 0; width: parent.width; text: "TOKENS BY MODEL"; foreground: root.foreground; fontFamily: root.fontFamily }
            Repeater {
              model: history.models
              ModelRow {
                required property var modelData
                width: history.width
                row: modelData
                share: modelData.total / Math.max(1, history.models[0].total)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // An agent's fuel card: mark, name and plan, then its gauges.
  component AgentCard: Rectangle {
    id: card
    property var agent: null
    readonly property var fuel: root.fuelWindows(agent)
    readonly property bool failing: !!agent && String(agent.usageStatusText || "") !== "" && fuel.main.length === 0

    // Tide: no box; the agent sits straight on the drawer.
    radius: Style.space(14)
    color: Motion.PanelMotion.tide ? "transparent" : root.alpha(root.foreground, 0.05)
    implicitHeight: cardCol.implicitHeight + (Motion.PanelMotion.tide ? Style.space(8) : Style.space(28))

    Column {
      id: cardCol
      x: Motion.PanelMotion.tide ? Style.space(2) : Style.space(14); y: Motion.PanelMotion.tide ? Style.space(4) : Style.space(14)
      width: parent.width - (Motion.PanelMotion.tide ? Style.space(4) : Style.space(28))
      spacing: Style.space(14)

      Row {
        spacing: Style.space(10)
        Rectangle {
          width: Style.space(28); height: width; radius: Style.space(8)
          color: Motion.PanelMotion.tide ? "transparent" : root.alpha(root.foreground, 0.08)
          Item {
            id: mark
            anchors.centerIn: parent
            width: Style.space(16); height: width
            property var candidates: root.iconCandidatesForProvider(card.agent, root.surface)
            property string candidatesKey: candidates.join("\n")
            property int candidateIndex: 0
            onCandidatesKeyChanged: candidateIndex = 0
            Image {
              id: markImage
              anchors.fill: parent
              source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
              sourceSize.width: 64; sourceSize.height: 64
              fillMode: Image.PreserveAspectFit
              onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
                Qt.callLater(function() { mark.candidateIndex++ })
            }
            Text {
              anchors.centerIn: parent
              visible: markImage.status !== Image.Ready
              text: button.text
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: card.agent ? card.agent.providerName : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Motion.PanelMotion.tide ? Style.space(15) : Style.font.body + 2
          font.weight: Motion.PanelMotion.tide ? Font.Medium : Font.DemiBold
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            var tier = card.agent ? String(card.agent.tierLabel || "") : ""
            return tier === "" ? "" : tier.charAt(0).toUpperCase() + tier.slice(1)
          }
          color: root.alpha(root.foreground, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      // Limits could not be read
      Text {
        visible: card.failing
        width: parent.width
        wrapMode: Text.WordWrap
        text: card.agent ? String(card.agent.usageStatusText || "") + (card.agent.authHelpText ? " · " + card.agent.authHelpText : "") : ""
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall + 1
      }

      // Prepaid credits drain the same way a limit does.
      Gauge {
        visible: !!card.agent && !!card.agent.balance && card.agent.balance.funded > 0
        width: parent.width
        label: "Credits"
        sub: card.agent && card.agent.balance ? root.balanceDetailText(card.agent.balance) : ""
        level: card.agent && card.agent.balance && card.agent.balance.funded > 0 ? root.clamp(card.agent.balance.remaining / card.agent.balance.funded, 0, 1) : -1
        big: true
      }

      Repeater {
        model: card.fuel.main
        Gauge {
          required property var modelData
          width: cardCol.width
          label: modelData.label
          sub: root.resetLine(modelData.window)
          level: root.leftOf(modelData.window)
          big: modelData.big
        }
      }

      Text {
        visible: text !== ""
        width: parent.width
        leftPadding: Style.space(2)
        text: {
          var bits = []
          for (var i = 0; i < card.fuel.extras.length; i++) {
            var w = card.fuel.extras[i]
            bits.push(w.title + " · " + Math.round(root.leftOf(w) * 100) + "% left")
          }
          if (card.fuel.weeklyOnly) bits.push("No 5-hour limit on this plan")
          return bits.join("   ")
        }
        color: root.alpha(root.foreground, 0.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption + 1
        elide: Text.ElideRight
      }

      // Banked resets: count, expiry, and a two-step "Use reset" button.
      Item {
        id: resetRow
        readonly property var credits: root.resetCredits(card.agent)
        property bool confirming: false
        readonly property bool usable: !!credits && !((credits.credits || []).length > 0 && credits.credits[0].usableNow === false)
        visible: !!credits
        width: parent.width
        height: Style.space(28)
        onVisibleChanged: confirming = false

        Timer { id: confirmTimer; interval: 4000; onTriggered: resetRow.confirming = false }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(2)
          anchors.right: resetButton.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰑐  " + root.resetCreditsLine(resetRow.credits)
          color: root.alpha(root.foreground, 0.72)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption + 1
          elide: Text.ElideRight
        }

        Rectangle {
          id: resetButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(24)
          width: resetLabel.implicitWidth + Style.space(20)
          radius: Style.space(8)
          color: resetRow.confirming ? root.alpha(Commons.Color.accent, resetMouse.containsMouse ? 0.42 : 0.3)
            : root.alpha(root.foreground, resetMouse.containsMouse ? 0.14 : 0.08)
          border.width: 1
          border.color: resetRow.confirming ? root.alpha(Commons.Color.accent, 0.7) : root.alpha(root.foreground, 0.12)
          opacity: usage.resetRunning || !resetRow.usable ? 0.6 : 1
          Text {
            id: resetLabel
            anchors.centerIn: parent
            text: usage.resetRunning && usage.resetProvider === card.agent.providerId ? "Resetting…" : (resetRow.confirming ? "Confirm reset" : "Use reset")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption + 1
            font.weight: Font.DemiBold
          }
          MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !usage.resetRunning && resetRow.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (!resetRow.confirming) { resetRow.confirming = true; confirmTimer.restart(); return }
              resetRow.confirming = false
              confirmTimer.stop()
              var c = (resetRow.credits.credits || [])[0]
              usage.useResetCredit(card.agent.providerId, c ? c.id : "")
            }
          }
          PanelToolTip { visible: resetMouse.containsMouse; text: root.resetCreditsTooltip(resetRow.credits); fontFamily: root.fontFamily }
        }
      }

      Text {
        visible: !!card.agent && card.agent.providerId === usage.resetProvider && usage.resetMessage !== ""
        width: parent.width
        leftPadding: Style.space(2)
        text: usage.resetMessage
        color: usage.resetMessage.indexOf("failed") >= 0 ? root.urgent : root.alpha(root.foreground, 0.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption + 1
        elide: Text.ElideRight
      }
    }
  }

  // One fuel gauge: label and reset on the left, "NN% left" on the right, and a
  // bar that starts full from the left edge and empties from the right.
  component Gauge: Column {
    id: gauge
    property string label: ""
    property string sub: ""
    property real level: -1
    property bool big: true
    readonly property color tint: root.fuelColor(Math.max(0, level))
    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: Math.max(gaugeLabels.implicitHeight, gaugeValue.implicitHeight)
      Column {
        id: gaugeLabels
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.right: gaugeValue.left
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(2)
        Text {
          text: gauge.label
          color: root.alpha(root.foreground, Motion.PanelMotion.tide ? 0.9 : 0.8)
          font.family: root.fontFamily
          font.pixelSize: Motion.PanelMotion.tide ? Style.space(14) : Style.font.bodySmall + 1
          font.weight: Motion.PanelMotion.tide ? Font.Medium : Font.DemiBold
        }
        Text {
          visible: text !== ""
          width: parent.width
          text: gauge.sub
          elide: Text.ElideRight
          color: root.alpha(root.foreground, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption + 1
        }
      }
      Row {
        id: gaugeValue
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(4)
        Text {
          // Tide: a big light number, the percent sign small beside it.
          text: gauge.level >= 0 ? Math.round(gauge.level * 100) + (Motion.PanelMotion.tide ? "<span style='font-size:" + Style.space(17) + "px'>%</span>" : "%") : "—"
          textFormat: Motion.PanelMotion.tide ? Text.StyledText : Text.PlainText
          color: gauge.level >= 0 && gauge.level <= 0.2 ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Motion.PanelMotion.tide ? (gauge.big ? Style.space(40) : Style.space(28)) : gauge.big ? Style.font.display + 4 : Style.font.title + 4
          font.weight: Motion.PanelMotion.tide ? Font.ExtraLight : Font.DemiBold
          font.letterSpacing: Motion.PanelMotion.tide ? -1 : -0.5
        }
        Text {
          anchors.baseline: parent.children[0].baseline
          text: "left"
          color: root.alpha(root.foreground, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall + 1
          font.weight: Font.Medium
        }
      }
    }

    // Tide: the fuel left is a wavy line that runs out into a hairline.
    Shape {
      id: wave
      visible: Motion.PanelMotion.tide
      width: parent.width
      height: Style.space(16)
      preferredRendererType: Shape.CurveRenderer
      readonly property real filled: gauge.level > 0 ? width * gauge.level : 0
      readonly property var points: {
        var pts = [], amp = height * 0.28, mid = height / 2, len = Math.max(0, filled - Style.space(6))
        for (var x = 0; x <= len; x += 2) pts.push(Qt.point(x + 1, mid + Math.sin(x / Style.space(9)) * amp))
        if (pts.length < 2) pts = [Qt.point(1, mid), Qt.point(1, mid)]
        return pts
      }
      ShapePath {
        strokeColor: gauge.level >= 0 && gauge.level <= 0.2 ? root.urgent : root.foreground
        strokeWidth: gauge.big ? 3 : 2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: wave.points }
      }
      Rectangle {
        x: wave.filled + Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, wave.width - x)
        height: 1
        color: root.alpha(root.foreground, 0.18)
      }
    }

    Rectangle {
      id: tank
      visible: !Motion.PanelMotion.tide
      width: parent.width
      height: gauge.big ? Style.space(8) : Style.space(5)
      radius: height / 2
      color: root.alpha(root.foreground, 0.08)
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: parent.radius
        width: gauge.level > 0 ? Math.max(parent.height, parent.width * gauge.level) : 0
        color: gauge.tint
        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }
      }
    }
  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }
}
