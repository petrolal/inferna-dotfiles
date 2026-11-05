import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "inferna.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\ue900"
    fontFamily: "inferna"
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("inferna-shell shell toggle inferna.menu '{\"menu\":\"root\"}'")
    }
  }
}
