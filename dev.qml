// Windowed preview: no locking, no PAM. Run: qs -p ~/.config/quickshell/solar-lock/dev.qml
import Quickshell
import QtQuick

ShellRoot {
    FloatingWindow {
        implicitWidth: 1280
        implicitHeight: 720
        Scene { anchors.fill: parent; onSubmit: pw => console.log("submit", pw.length, "chars") }
    }
}
