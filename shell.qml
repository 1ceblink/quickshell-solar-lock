// The real lockscreen. Run: qs -p ~/.config/quickshell/solar-lock/shell.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick

ShellRoot {
    id: root
    // Never hot-reload while locked: a reload destroys the lock object and leaves a stuck process
    settings.watchFiles: false
    property bool failed: false
    property bool busy: false
    property bool unlocking: false

    PamContext {
        id: pam
        config: "hyprlock"          // reuses /etc/pam.d/hyprlock
        property string pending: ""
        onPamMessage: if (responseRequired) respond(pending)
        onCompleted: result => {
            root.busy = false
            if (result === PamResult.Success) {
                root.unlocking = true        // Scene fades out, then emits unlocked()
            } else {
                root.failed = true
            }
        }
    }

    // SOLAR_LOCK_SCREEN: show the scene only on the screen whose output name or model contains this text
    // (e.g. "HDMI-A-1" or "G24-20"); the other screens stay black. Unset, or no screen matches: every screen.
    readonly property string onlyScreen: Quickshell.env("SOLAR_LOCK_SCREEN") || ""
    function isMain(s) { return !!s && (s.name + " " + s.model).indexOf(onlyScreen) >= 0 }
    readonly property bool filtered: onlyScreen !== "" && Quickshell.screens.some(s => isMain(s))
    signal forwardKey(var event)                 // keys typed on a blank screen

    WlSessionLock {
        id: lock
        locked: true
        WlSessionLockSurface {
            id: surface
            color: "black"
            readonly property bool main: !root.filtered || root.isMain(surface.screen)
            Item {                                  // blank screen: keys typed while it has focus go to the scene
                anchors.fill: parent
                visible: !surface.main
                focus: !surface.main
                Keys.onPressed: event => { root.forwardKey(event) }
            }
            Loader {
                id: sceneLoader
                anchors.fill: parent
                active: surface.main
                focus: surface.main
                sourceComponent: mainComp
                Connections {
                    target: root
                    function onForwardKey(event) { if (sceneLoader.item) sceneLoader.item.handleKey(event) }
                }
            }
        }
    }
    Component {
        id: mainComp
        Scene {
            anchors.fill: parent
            failed: root.failed
            busy: root.busy
            unlocking: root.unlocking
            onUnlocked: {
                lock.locked = false
                Qt.callLater(Qt.quit)
            }
            onEdited: root.failed = false
            onSubmit: pw => {
                root.failed = false
                root.busy = true
                pam.pending = pw
                pam.start()
            }
        }
    }
}
