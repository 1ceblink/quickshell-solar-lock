// The real lockscreen. Run: qs -p ~/.config/quickshell/solar-lock/shell.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick

ShellRoot {
    id: root
    // Never hot-reload while locked: a reload destroys the lock object and leaves a stuck process
    settings.watchFiles: false
    property bool failed: false
    property bool busy: false
    property bool unlocking: false
    property bool capsLock: false
    property string layoutCode: ""

    // The theme you picked last time: kept in ~/.local/state/quickshell-solar-lock/theme (one word)
    readonly property string themePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell-solar-lock/theme"
    FileView { id: themeFile; path: root.themePath; blockLoading: true; printErrors: false }
    readonly property string savedTheme: { try { return themeFile.text().trim() } catch (e) { return "" } }
    Process {
        id: saveTheme
        property string value: ""
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", root.themePath, value]   // the theme name is a plain argument, never part of the script
    }

    // Caps Lock and the active keyboard layout, from Hyprland (nothing is shown if hyprctl is unavailable)
    Process {
        id: kbProbe
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var kbs = JSON.parse(text).keyboards
                    var main = kbs.find(k => k.main) || kbs[0]
                    root.capsLock = kbs.some(k => k.capsLock)
                    var codes = main.layout.split(",")
                    root.layoutCode = (codes[main.active_layout_index] || "").trim().toUpperCase()
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 400; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!kbProbe.running) kbProbe.running = true
    }

    PamContext {
        id: pam
        config: "hyprlock"          // reuses /etc/pam.d/hyprlock
        property string pending: ""
        onPamMessage: if (responseRequired) respond(pending)
        onCompleted: result => {
            pending = ""                  // the password is not kept once PAM has finished
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
            capsLock: root.capsLock
            layoutCode: root.layoutCode
            busy: root.busy
            unlocking: root.unlocking
            startTheme: root.savedTheme
            onThemeSelected: name => { saveTheme.value = name; saveTheme.running = true }
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
