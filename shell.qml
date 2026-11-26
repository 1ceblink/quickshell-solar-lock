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

    WlSessionLock {
        id: lock
        locked: true
        WlSessionLockSurface {
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
}
