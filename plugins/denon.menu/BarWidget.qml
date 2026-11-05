import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar button for the menu: the stock Inferna logo glyph.
BarWidget {
  id: root
  moduleName: "inferna.menu"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontFamily: "inferna"
    horizontalMargin: 7.5
    tooltipText: "Menu"
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("inferna-shell shell toggle inferna.menu '{\"menu\":\"root\"}'")
    }
  }
}
