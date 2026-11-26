/*
    Solar-system lockscreen for KDE Plasma's screen locker (kscreenlocker_greet).

    KDE keeps doing the actual locking (the compositor, multi-monitor, crash recovery); this file only
    replaces the UI. It talks to the greeter's `authenticator` object the same way the stock Plasma
    lockscreen (org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml) does.

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

Item {
    id: root

    // Properties and signals kscreenlocker_greet looks for on the root item
    property bool debug: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()
    property bool viewVisible: false

    implicitWidth: 800
    implicitHeight: 600

    Scene {
        id: scene
        anchors.fill: parent
        focus: true

        // the user typed again: drop the "wrong password" state (Scene asks, it never clears it itself)
        onEdited: scene.failed = false
        onSubmit: pw => {
            scene.failed = false
            scene.busy = true
            authenticator.respond(pw)
        }
        // Scene has faded to black; the greeter exits and KDE unlocks the session
        onUnlocked: Qt.quit()
    }

    Connections {
        target: authenticator

        function onFailed(kind) {
            if (kind !== 0) { // non-interactive authenticators (fingerprint, smartcard) report failures here too
                return
            }
            scene.busy = false
            scene.failed = true
            scene.password = ""
            authenticator.startAuthenticating()
        }

        function onSucceeded() {
            // stop every pending authenticator so nothing times out after unlock
            authenticator.stopAuthenticating()
            scene.busy = false
            scene.unlocking = true
        }
    }

    // keep the PAM conversation alive, like the stock lockscreen's heartbeat
    Timer {
        interval: 1000
        running: !authenticator.unlocked
        repeat: true
        triggeredOnStart: true
        onTriggered: authenticator.startAuthenticating()
    }

    onClearPassword: scene.password = ""

    Component.onCompleted: scene.forceActiveFocus()
}
