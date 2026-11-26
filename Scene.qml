import QtQuick
import QtQuick3D
import QtQuick.Window

Rectangle {
    id: root
    color: Qt.rgba(0.059 * (1 - space), 0.047 * (1 - space), 0.122 * (1 - space), 1)
    focus: true

    property string password: ""
    property bool failed: false
    property bool busy: false
    property bool unlocking: false
    property int selected: -1          // -2 = Sun, -3 = the Moon, 0.. = the theme's bodies, -1 = none (overview)

    // ---- supernova ------------------------------------------------------------------------------------------
    // Every `novaInterval` ms of being locked the Sun goes supernova, seen from the normal overview (no zoom).
    // Everything is real 3D (spheres, no flat images): the textured Sun slowly shrinks and turns
    // into a small white sphere; it ignites blue as a small sphere and swells slowly in a growing glow;
    // then the whole screen blows out white, fades to black, and after a pause everything fades back in.
    // The planets are never touched.
    property int novaInterval: 22 * 60 * 1000
    property real novaBuild: 0         // 0 -> 1: the textured Sun shrinks and turns into the small white sphere
    property real novaBlue: 0          // 0 -> 1: white turns blue
    property real novaGrow: 0          // 0 -> 1: swells slowly (about 2.8 s); still growing when the blast starts
    property real blastGlow: 0         // 0 -> 1: the flood of light that fills the screen
    readonly property bool novaOn: novaBuild > 0.001
    readonly property real space: novaOn ? Math.min(1, novaBuild * 1.2) : 0   // background and UI fade to black space
    readonly property real sunScale: (1 - 0.55 * novaBuild) * (1 - 0.45 * novaBlue) * (1 + 0.6 * novaGrow)
    readonly property real heat: Math.max(0, Math.min(1, (novaGrow - 0.02) / 0.32))   // the lit white-blue star builds up as it swells
    readonly property real sunR: 3.5 * sunScale
    property real fxTime: 0            // seconds, advanced every frame (gentle wobble and drift)
    readonly property vector3d sunS: Qt.vector3d(0.07 * sunScale * (1 + (0.025 + 0.06 * novaBuild) * Math.sin(fxTime * 1.3)),
                                                 0.07 * sunScale * (1 + (0.025 + 0.06 * novaBuild) * Math.sin(fxTime * 1.9 + 1.0)),
                                                 0.07 * sunScale * (1 + (0.025 + 0.06 * novaBuild) * Math.sin(fxTime * 1.6 + 2.0)))
    // orange -> yellow -> white while it shrinks, then white -> blue
    readonly property color novaColor: {
        var r0, g0, b0
        if (novaBuild < 0.5) {
            var k = novaBuild * 2
            r0 = 1.0; g0 = 0.635 + (0.86 - 0.635) * k; b0 = 0.227 + (0.38 - 0.227) * k
        } else {
            var k2 = (novaBuild - 0.5) * 2
            r0 = 1.0; g0 = 0.86 + (0.97 - 0.86) * k2; b0 = 0.38 + (0.92 - 0.38) * k2
        }
        return Qt.rgba(r0 + (0.40 - r0) * novaBlue, g0 + (0.80 - g0) * novaBlue, b0 + (1.0 - b0) * novaBlue, 1)
    }
    // small body: orange -> cream -> white while shrinking, deep blue at ignition, then white-hot as it swells
    readonly property color coreCol: Qt.rgba((Math.min(1, novaColor.r + 0.5) * (1 - novaBlue) + 0.22 * novaBlue) * (1 - hot) + 0.9 * hot,
                                             (Math.min(1, novaColor.g + 0.4) * (1 - novaBlue) + 0.50 * novaBlue) * (1 - hot) + 0.96 * hot,
                                             (Math.min(1, novaColor.b + 0.3) * (1 - novaBlue) + 1.0 * novaBlue) * (1 - hot) + 1.0 * hot, 1)
    readonly property real hot: Math.max(0, Math.min(1, (novaGrow - 0.15) / 0.8))
    readonly property color haloCol: Qt.rgba(novaColor.r * (1 - 0.7 * novaBlue), novaColor.g * (1 - 0.5 * novaBlue), novaColor.b, 1)
    property bool sceneReady: false   // 3D view is enabled one frame after the first (black) frame
    property int framesSeen: 0
    readonly property real homeZ: 130   // camera distance that fits the whole system
    signal submit(string password)
    signal unlocked()
    signal edited()   // user typed again: the shell clears its `failed` flag (never assign a bound property here)

    // ---- themes ---------------------------------------------------------------------------------------------
    // Each theme is its own file with its bodies and their descriptions; the Sun and the supernova are shared.
    // `theme` is the one shown when the lock starts; Up/Down (with an empty password) or the corner button switch it.
    property string theme: "solar"
    readonly property var themes: ["solar", "hearthian"]
    readonly property var system: systemLoader.item
    readonly property var planets: system ? system.planets : []
    readonly property var sunInfo: system ? system.sunInfo : ({ "name": "Sun", "size": 3.5, "color": "#ffb12e", "desc": "" })
    readonly property var moonInfo: system ? system.moonInfo : null   // the solar theme's Moon (target -3); null if none
    readonly property bool blackout: veil.opacity > 0.97 || flash.opacity > 0.97   // nothing in the scene can be seen

    // fade to black, swap the theme, fade back in. step: +1 = next, -1 = previous
    function switchTheme(step) {
        if (unlocking || themeAnim.running) return
        nextTheme = themes[(themes.indexOf(theme) + step + themes.length) % themes.length]
        themeAnim.start()
    }
    property string nextTheme: theme
    property bool flying: false        // true while the camera is flying in or out: no description card then

    property int hovered: -1
    property point hoverPos: Qt.point(-1, -1)
    property real ringX: 0
    property real ringY: 0
    property real ringR: 20

    function tex(name) { return Qt.resolvedUrl("textures/" + name) }

    function orbitText(p) {
        var days = Math.round(p.year * 365)
        return p.au + " AU from the Sun \u00b7 year: " + (p.year < 1 ? days + " days" : p.year === 1 ? "365 days" : p.year + " earth years")
    }

    // screen-space description of a target: centre, rough radius and the reach we accept for clicks
    function screenOf(i) {
        var pos = i === -2 ? Qt.vector3d(0, 0, 0) : system ? system.bodyPos(i) : null
        if (!pos) return null
        var sp = view.mapFrom3DScene(pos)
        if (sp.z <= 0) return null
        var size = i === -3 ? moonInfo.size : i === -2 ? sunR : planets[i].size   // sunR follows the supernova's shrink and swell
        var r = size * (height / 2) / (0.364 * (sp.z + cam.clipNear))
        return { x: sp.x, y: sp.y, z: sp.z, r: r, reach: Math.max(i === -3 || size < 0.6 ? 14 : 26, r * 1.15) }
    }

    function hitTest(px, py) {
        var best = -1, bestScore = 1e9
        for (var i = -3; i < planets.length; i++) {
            if (i === -1) continue
            var t = screenOf(i)
            if (!t) continue
            var d = Math.hypot(t.x - px, t.y - py)
            if (d < t.reach && d / t.reach < bestScore) { bestScore = d / t.reach; best = i }
        }
        return best
    }

    // plain Qt clock (no Quickshell types) so the same scene also runs inside KDE's screen locker
    QtObject { id: clock; property date date: new Date() }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { var n = new Date(); if (Math.floor(n / 60000) !== Math.floor(clock.date / 60000)) clock.date = n }
    }

    // sparse static starfield
    Repeater {
        model: 90
        Rectangle {
            x: Math.random() * root.width
            y: Math.random() * root.height
            width: Math.random() < 0.12 ? 2 : 1
            height: width
            radius: width / 2
            color: "#fff1d6"
            opacity: 0.12 + Math.random() * 0.4
        }
    }

    View3D {
        id: view
        anchors.fill: parent
        visible: root.sceneReady
        camera: cam
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
            tonemapMode: SceneEnvironment.TonemapModeNone
        }

        Node {
            id: origin
            eulerRotation.x: -38
            eulerRotation.y: 20
            PerspectiveCamera {
                id: cam
                z: root.homeZ
                // near/far follow the zoom: a fixed near plane (default 10) clips close planets entirely
                clipNear: Math.max(0.5, z * 0.22)
                clipFar: z + 170
                fieldOfView: 40
            }
        }

        PointLight {
            brightness: 1.75
            constantFade: 1
            linearFade: 0
            quadraticFade: 0
            ambientColor: "#4a3a63"
        }

        // sun: textured core plus a few translucent shells for a soft glow
        Node {
            id: sun
            property real glow: root.hovered === -2 ? 1 : 0
            Behavior on glow { NumberAnimation { duration: 160 } }
            Model {
                property int planetIndex: -2
                source: "#Sphere"
                scale: root.sunS
                opacity: 1 - Math.max(0, Math.min(1, (root.novaBuild - 0.1) / 0.85))
                pickable: true
                materials: DefaultMaterial {
                    lighting: DefaultMaterial.NoLighting
                    diffuseMap: Texture { source: root.tex("2k_sun.jpg"); generateMipmaps: true; mipFilter: Texture.Linear }
                }
                NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 240000; loops: Animation.Infinite }
            }
            Repeater3D {
                model: [ { s: 0.078, o: 0.16, b: -2 }, { s: 0.092, o: 0.08, b: -1 }, { s: 0.115, o: 0.04, b: 0 } ]
                Model {
                    required property var modelData
                    source: "#Sphere"
                    scale: Qt.vector3d(modelData.s * root.sunScale, modelData.s * root.sunScale, modelData.s * root.sunScale)
                    opacity: modelData.o * (1 + 1.8 * sun.glow + 3.0 * root.novaBuild) * (1 - root.heat)
                    depthBias: modelData.b
                    pickable: false
                    materials: DefaultMaterial {
                        lighting: DefaultMaterial.NoLighting
                        diffuseColor: root.haloCol
                    }
                }
            }

            // ---- the small white sphere the Sun turns into (and the white-hot core after ignition) ----
            Model {
                visible: root.novaOn
                source: "#Sphere"
                scale: root.sunS.times(1.003)
                opacity: Math.min(1, Math.max(0, (root.novaBuild - 0.3) / 0.65))
                depthBias: -2
                pickable: false
                materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; diffuseColor: root.coreCol }
            }
            // ===== the swelling: the star stays small, and a soft blue glow builds around it in many thin 3D shells
            // (seen from behind only, so they never cover the star itself) =====
            Repeater3D {
                model: 22
                Model {
                    required property int index
                    visible: root.heat > 0.02
                    source: "#Sphere"
                    scale: Qt.vector3d(root.sunR * (1.12 + index * 0.17) * (1 + 0.9 * root.novaGrow) / 50, root.sunR * (1.12 + index * 0.17) * (1 + 0.9 * root.novaGrow) / 50, root.sunR * (1.12 + index * 0.17) * (1 + 0.9 * root.novaGrow) / 50)
                    opacity: 0.05 * Math.pow(1 - index / 23, 1.7) * root.heat * (0.6 + 0.4 * root.novaGrow) * (1 - 0.4 * root.blastGlow)
                    depthBias: -4 - index * 0.2
                    pickable: false
                    materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; cullMode: Material.FrontFaceCulling; diffuseColor: index < 7 ? "#7fb2ff" : "#2f6bff" }
                }
            }
            Repeater3D {   // tight bright corona close to the star
                model: 6
                Model {
                    required property int index
                    visible: root.heat > 0.02
                    source: "#Sphere"
                    scale: root.sunS.times(1.05 + index * 0.12)
                    opacity: 0.18 * (1 - index * 0.15) * root.heat
                    depthBias: -2.5 - index * 0.1
                    pickable: false
                    materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; cullMode: Material.FrontFaceCulling; diffuseColor: "#cfe6ff" }
                }
            }
            // the blast: a fireball that floods outward, white-hot inside and blue at its leading edge, until it fills the screen
            Repeater3D {
                model: 6
                Model {
                    required property int index
                    visible: root.blastGlow > 0.001
                    source: "#Sphere"
                    scale: Qt.vector3d((root.sunR * 2.2 + root.blastGlow * (1.0 - index * 0.07) * 70) / 50, (root.sunR * 2.2 + root.blastGlow * (1.0 - index * 0.07) * 70) / 50, (root.sunR * 2.2 + root.blastGlow * (1.0 - index * 0.07) * 70) / 50)
                    opacity: 0.16 * Math.min(1, root.blastGlow * 3)
                    depthBias: -10 - index * 0.2
                    pickable: false
                    materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; cullMode: Material.BackFaceCulling; diffuseColor: Qt.rgba(1 - 0.5 * index / 5, 1 - 0.31 * index / 5, 1, 1) }
                }
            }
        }

        // the theme's own bodies (planets, moons, belts, orbits); only one theme is loaded at a time
        Loader3D {
            id: systemLoader
            sourceComponent: root.theme === "hearthian" ? hearthianComp : solarComp
        }
        Component { id: solarComp; SolarSystem { scene: root } }
        Component { id: hearthianComp; HearthianSystem { scene: root } }

        // glide the camera pivot toward the selected body (or back to the centre)
        FrameAnimation {
            running: true
            onTriggered: {
                var t = Qt.vector3d(0, 0, 0)
                if (root.selected !== -1 && root.selected !== -2 && root.system) {
                    var o = root.system.bodyPos(root.selected)
                    if (o) t = o
                }
                root.fxTime += frameTime
                var k = Math.min(1, frameTime * 5)
                origin.position = Qt.vector3d(
                    origin.position.x + (t.x - origin.position.x) * k,
                    origin.position.y + (t.y - origin.position.y) * k,
                    origin.position.z + (t.z - origin.position.z) * k)
            }
        }
    }

    NumberAnimation { id: zoomAnim; target: cam; property: "z"; duration: 900; easing.type: Easing.InOutCubic }
    Timer { id: flyTimer; interval: 1150; onTriggered: root.flying = false }   // the camera has arrived (or is back out): the card may show

    // click a body to zoom in on it; click it again (or empty space) to return to the overview
    function select(i) {
        introZoom.stop()
        if (i === selected) i = -1
        selected = i
        flying = true
        flyTimer.restart()
        zoomAnim.stop()
        zoomAnim.to = i === -3 ? moonInfo.size * 5 + 5 : i === -2 ? sunInfo.size * 5 + 6 : i >= 0 ? planets[i].size * 5 + 5 : homeZ
        zoomAnim.start()
    }

    WheelHandler {
        onWheel: event => {
            introZoom.stop()
            zoomAnim.stop()
            cam.z = Math.max(4, Math.min(220, cam.z * (event.angleDelta.y > 0 ? 0.9 : 1.1)))
        }
    }
    TapHandler {
        onTapped: eventPoint => {
            var p = eventPoint.position
            if (themeButton.contains(themeButton.mapFromItem(root, p.x, p.y))) { root.switchTheme(1); return }
            root.select(root.hitTest(p.x, p.y))
        }
    }

    HoverHandler {
        id: hover
        cursorShape: root.hovered !== -1 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPointChanged: root.hoverPos = point.position
        onHoveredChanged: if (!hovered) root.hovered = -1
    }
    // every frame: re-test what is under the cursor (planets move under a still mouse) and keep the card
    // anchored to the hovered body, or to the zoomed-in body when nothing is hovered
    FrameAnimation {
        running: hover.hovered || root.selected !== -1
        onTriggered: {
            if (hover.hovered) root.hovered = root.hitTest(root.hoverPos.x, root.hoverPos.y)
            var t = root.shownIndex !== -1 ? root.screenOf(root.shownIndex) : null
            if (t) { root.ringX = t.x; root.ringY = t.y; root.ringR = Math.max(16, t.r * 1.25 + 5) }
        }
    }

    // tooltip card next to the hovered body
    // the hovered body wins; otherwise the zoomed-in one keeps its card without hovering
    readonly property int shownIndex: flying ? -1 : (hovered !== -1 ? hovered : selected)
    property int tipIndex: -1
    onShownIndexChanged: if (shownIndex !== -1) tipIndex = shownIndex
    readonly property var tipInfo: tipIndex === -3 ? moonInfo : tipIndex === -2 ? sunInfo : tipIndex >= 0 ? planets[tipIndex] : null

    Rectangle {
        id: tip
        readonly property bool flip: root.ringX + root.ringR + 14 + width > root.width - 20
        width: 270
        height: tipCol.implicitHeight + 28
        x: flip ? root.ringX - root.ringR - 14 - width : root.ringX + root.ringR + 14
        y: Math.max(10, Math.min(root.height - height - 10, root.ringY - height / 2))
        radius: 12
        color: "#1d1632"
        border.width: 0.5
        border.color: root.tipInfo ? Qt.alpha(root.tipInfo.color, 0.7) : "#b3fff1d6"
        opacity: (root.shownIndex !== -1 && !root.novaOn) ? 0.95 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Column {
            id: tipCol
            x: 16; y: 14
            width: parent.width - 32
            spacing: 6
            Text {
                text: root.tipInfo ? root.tipInfo.name.toUpperCase() : ""
                color: "#fff1d6"; font.pixelSize: 14; font.letterSpacing: 4
            }
            Text {
                width: parent.width
                text: root.tipInfo ? (root.tipInfo.meta !== undefined ? root.tipInfo.meta : root.orbitText(root.tipInfo)) : ""
                color: "#fff1d6"; opacity: 0.55; font.pixelSize: 11; wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: root.tipInfo ? root.tipInfo.desc : ""
                color: "#fff1d6"; opacity: 0.88; font.pixelSize: 13; lineHeight: 1.2; wrapMode: Text.WordWrap
            }
        }
    }

    // clock
    Column {
        opacity: 1 - root.space
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.03
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: "#fff1d6"
            font.family: "Scenesa"
            font.pixelSize: 84; font.letterSpacing: 4
            style: Text.Outline; styleColor: "#1b1230"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, "dddd, d MMMM").toUpperCase()
            color: "#fff1d6"; opacity: 0.7
            font.family: "Scenesa"
            font.pixelSize: 15; font.letterSpacing: 5
        }
    }

    // password pill: dots, or a status hint when empty
    Rectangle {
        id: pill
        opacity: 1 - 0.85 * root.space
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        anchors.horizontalCenter: parent.horizontalCenter
        height: 38
        width: Math.max(168, dots.width + 44)
        radius: height / 2
        color: "#c71d1632"
        border.width: 1
        border.color: root.failed ? "#99e07a7a" : "#40fff1d6"
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Row {
            id: dots
            anchors.centerIn: parent
            spacing: 5
            Repeater {
                model: root.password.length
                Rectangle { width: 8; height: 8; radius: 4; color: "#fff1d6" }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: root.password.length === 0
            text: root.busy ? "checking\u2026" : root.failed ? "wrong password" : "type password"
            color: root.failed ? "#e88a8a" : "#fff1d6"
            opacity: root.failed || root.busy ? 0.9 : 0.4
            font.pixelSize: 13; font.letterSpacing: 2
        }
    }

    // theme switcher in the bottom-right corner (taps are handled by the main TapHandler above)
    Rectangle {
        id: themeButton
        opacity: (themeHover.hovered ? 0.95 : 0.6) * (1 - 0.85 * root.space)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        height: 34
        width: themeLabel.implicitWidth + 32
        radius: height / 2
        color: "#c71d1632"
        border.width: 1
        border.color: "#40fff1d6"
        Behavior on opacity { NumberAnimation { duration: 140 } }
        HoverHandler { id: themeHover; cursorShape: Qt.PointingHandCursor }
        Text {
            id: themeLabel
            anchors.centerIn: parent
            text: "\u25b4\u25be  " + (root.system ? root.system.title : "").toUpperCase()
            color: "#fff1d6"
            font.pixelSize: 12; font.letterSpacing: 2
        }
    }

    // fade in from black on lock, fade out to black before unlocking
    Rectangle {
        id: veil
        anchors.fill: parent
        z: 1000
        color: "#05040a"
        opacity: 1
    }
    NumberAnimation { id: fadeIn; target: veil; property: "opacity"; from: 1; to: 0; duration: 1000; easing.type: Easing.OutCubic }
    NumberAnimation { id: fadeOut; target: veil; property: "opacity"; to: 1; duration: 250; easing.type: Easing.InOutQuad; onFinished: root.unlocked() }
    NumberAnimation { id: introZoom; target: cam; property: "z"; from: 175; to: root.homeZ; duration: 1800; easing.type: Easing.OutCubic }
    // white-blue flash that covers the whole screen at the blast; the black veil then fades in over it
    Rectangle { id: flash; anchors.fill: parent; z: 999; color: "#e6f4ff"; opacity: 0 }

    function resetNova() { novaBuild = 0; novaBlue = 0; novaGrow = 0; blastGlow = 0; flash.opacity = 0 }
    function resetView() { introZoom.stop(); selected = -1; zoomAnim.stop(); zoomAnim.to = homeZ; zoomAnim.start() }   // back to the overview

    SequentialAnimation {
        id: novaAnim
        ScriptAction { script: root.resetView() }                                                                       // back to the overview if zoomed in
        NumberAnimation { target: root; property: "novaBuild"; to: 1; duration: 8200; easing.type: Easing.InOutQuad }   // texture slowly becomes the small white sphere
        NumberAnimation { target: root; property: "novaBlue"; to: 1; duration: 1400; easing.type: Easing.InOutSine }    // ignites blue
        ParallelAnimation {                                                                                             // swell and blast as one continuous motion
            NumberAnimation { target: root; property: "novaGrow"; to: 1.0; duration: 2800; easing.type: Easing.Linear }
            SequentialAnimation {
                PauseAnimation { duration: 2500 }
                ParallelAnimation {
                    NumberAnimation { target: root; property: "blastGlow"; from: 0; to: 1; duration: 450; easing.type: Easing.InQuad }
                    NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 300; easing.type: Easing.InQuad }
                }
            }
        }
        PauseAnimation { duration: 350 }
        NumberAnimation { target: veil; property: "opacity"; to: 1; duration: 1100; easing.type: Easing.InOutQuad }    // white fades to black
        ScriptAction { script: root.resetNova() }
        PauseAnimation { duration: 2500 }                                                                               // the black moment
        ParallelAnimation {                                                                                             // everything comes back
            NumberAnimation { target: veil; property: "opacity"; to: 0; duration: 1600; easing.type: Easing.OutCubic }
            ScriptAction { script: introZoom.restart() }
        }
    }
    SequentialAnimation {
        id: themeAnim
        ScriptAction { script: { novaAnim.stop(); fadeIn.stop(); introZoom.stop() } }
        NumberAnimation { target: veil; property: "opacity"; to: 1; duration: 220; easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                novaAnim.stop()                              // in case the nova timer fired during the fade
                root.resetNova()
                root.hovered = -1
                root.selected = -1
                zoomAnim.stop()
                cam.z = root.homeZ
                root.theme = root.nextTheme
                novaTimer.restart()                          // a new theme gets a full 22 minutes before its supernova
            }
        }
        PauseAnimation { duration: 120 }                     // the new theme's first (heavy) frame happens under the veil
        NumberAnimation { target: veil; property: "opacity"; to: 0; duration: 700; easing.type: Easing.OutCubic }
    }
    Timer {
        id: novaTimer
        interval: root.novaInterval
        running: root.sceneReady && !root.unlocking
        repeat: true
        onTriggered: if (!novaAnim.running) novaAnim.start()
    }

    // Qt Quick 3D's one-off setup stalls the first frame by ~240 ms. Show the black lock surface straight
    // away (so the desktop is covered at once), enable the 3D view on the next frame, and start the
    // fade-in only after that heavy frame has been presented.
    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            root.framesSeen++
            if (root.framesSeen === 1) {
                root.sceneReady = true
            } else if (root.framesSeen === 2 && !root.unlocking) {
                fadeIn.start()
                introZoom.start()
            }
        }
    }
    onUnlockingChanged: if (unlocking) { novaAnim.stop(); themeAnim.stop(); resetNova(); fadeIn.stop(); fadeOut.start() }

    Keys.onPressed: event => {
        if (root.busy || root.unlocking) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (password.length > 0) { root.submit(password); password = "" }
        } else if (event.key === Qt.Key_Backspace) {
            password = (event.modifiers & Qt.ControlModifier) ? "" : password.slice(0, -1)   // Ctrl+Backspace clears everything
        } else if (event.key === Qt.Key_Escape) {
            if (root.selected !== -1) root.select(root.selected)   // Esc first leaves the zoom ...
            else password = ""                                     // ... and otherwise clears the password
        } else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && password.length === 0) {
            root.switchTheme(event.key === Qt.Key_Up ? 1 : -1)   // only with an empty password, so typing can never trigger it
        } else if (event.text.length === 1 && event.text >= " ") {
            root.edited()
            password += event.text
        }
    }
}
