import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property var shell: null
  property string infernaPath: Quickshell.env("INFERNA_PATH")

  readonly property int batteryThreshold: 10
  property string pendingPowerSource: ""

  PersistentProperties {
    id: persisted
    reloadableId: "inferna-battery"
    property bool notifiedLowBattery: false
  }

  function batteryPercentage() {
    return BatteryModel.batteryPercentage(UPower.displayDevice)
  }

  function isDischarging() {
    return BatteryModel.isDischarging(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging)
  }

  // Critical notifications do not expire. Clear this warning on AC, including
  // a restored popup after shell reload. Leave every other notification alone.
  function clearWarningOnPower() {
    if (UPower.onBattery || dismissWarningProcess.running) return
    dismissWarningProcess.running = true
  }

  function checkBattery() {
    clearWarningOnPower()
    var state = BatteryModel.shouldWarnLowBattery(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging, batteryThreshold, persisted.notifiedLowBattery)
    persisted.notifiedLowBattery = state.notifiedLowBattery
    if (state.notify) sendLowBatteryWarning(state.level)
  }

  function sendLowBatteryWarning(level) {
    if (warningProcess.running) return
    warningProcess.command = [
      "inferna-battery-low",
      String(level)
    ]
    warningProcess.running = true
  }

  function applyPowerProfile() {
    pendingPowerSource = UPower.onBattery ? "battery" : "ac"
    if (!powerProfileProcess.running) runPendingPowerProfile()
  }

  function runPendingPowerProfile() {
    powerProfileProcess.command = ["inferna-powerprofiles-set", pendingPowerSource]
    pendingPowerSource = ""
    powerProfileProcess.running = true
  }

  Process {
    id: warningProcess
    // The charger can arrive while the warning command is still sending.
    // Check again after it finishes so that late popup is cleared as well.
    onExited: root.clearWarningOnPower()
  }

  Process {
    id: dismissWarningProcess
    command: ["inferna-shell", "notifications", "dismiss", "Time to recharge!"]
  }

  Process {
    id: powerProfileProcess
    onExited: if (root.pendingPowerSource !== "") root.runPendingPowerProfile()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkBattery()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.checkBattery()
      root.applyPowerProfile()
    }
  }
}
