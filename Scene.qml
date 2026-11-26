import QtQuick
import QtQuick3D
import QtQuick.Window
import Quickshell

Rectangle {
    id: root
    color: "#0f0c1f"
    focus: true

    property string password: ""
    property bool failed: false
    property bool busy: false
    property bool unlocking: false
    property int selected: -1          // -2 = Sun, 0..7 = planets, -1 = none (overview)
    property bool sceneReady: false   // 3D view is enabled one frame after the first (black) frame
    property int framesSeen: 0
    readonly property real homeZ: 130   // camera distance that fits the whole system
    signal submit(string password)
    signal unlocked()
    signal edited()   // user typed again: the shell clears its `failed` flag (never assign a bound property here)

    // dist/size are artistic, not to scale. tilt = axial tilt (deg), spin = seconds per rotation (negative = retrograde)
    readonly property var planets: [
        { name: "Mercury", dist: 7,    size: 0.8,  tex: "2k_mercury.jpg", normal: "mercury_n.png", tilt: 0,   spin: 120, year: 0.24, au: 0.39, color: "#bda98f",
          desc: "The smallest planet and the closest to the Sun. A year here lasts just 88 days, yet a single day lasts 176 Earth days." },
        { name: "Venus",   dist: 10.5, size: 1.25, tex: "2k_venus_atmosphere.jpg", tilt: 177, spin: 200, year: 0.62, au: 0.72, color: "#e8c27c", atmo: "#ffe0a8", ao: 0.14,
          desc: "The hottest planet, around 465 \u00b0C under thick clouds of acid. It spins backwards, so the Sun rises in the west." },
        { name: "Earth",   dist: 15,   size: 1.35, tex: "2k_earth_daymap.jpg", tilt: 23,  spin: 40,  year: 1.0,  au: 1.0,  color: "#3a8cbd", clouds: true, moon: true, atmo: "#8cc4ff", ao: 0.12,
          desc: "Home, and the only world known to host life. Oceans cover 71% of its surface, and the Moon keeps its tilt steady." },
        { name: "Mars",    dist: 19,   size: 1.0,  tex: "2k_mars.jpg", normal: "mars_n.png", tilt: 25,  spin: 41,  year: 1.88, au: 1.52, color: "#c9653c", atmo: "#ffa874", ao: 0.06,
          desc: "A cold, rusty desert with the tallest volcano in the system: Olympus Mons, about 22 km high." },
        { name: "Jupiter", dist: 27,   size: 3.0,  tex: "2k_jupiter.jpg", flat: 0.935, tilt: 3,   spin: 16,  year: 11.86, au: 5.2, color: "#cc8c54",
          desc: "A gas giant bigger than all the other planets combined. Its Great Red Spot is a storm that has raged for centuries." },
        { name: "Saturn",  dist: 35,   size: 2.5,  tex: "2k_saturn.jpg", flat: 0.90, tilt: 27,  spin: 18,  year: 29.4, au: 9.58, color: "#e3c57c", rings: true,
          desc: "Famous for its rings of ice and rock. It is so light for its size that it would float in a big enough bathtub." },
        { name: "Uranus",  dist: 42,   size: 1.9,  tex: "2k_uranus.jpg", flat: 0.977, tilt: 98,  spin: -30, year: 84,   au: 19.2, color: "#a6e4df", atmo: "#a8f0ec", ao: 0.1,
          desc: "An ice giant rolling around the Sun on its side, tilted 98\u00b0. Each of its seasons lasts about 21 years." },
        { name: "Neptune", dist: 48,   size: 1.9,  tex: "2k_neptune.jpg", flat: 0.983, tilt: 28,  spin: 24,  year: 165,  au: 30.1, color: "#3f60d2", atmo: "#7f9cff", ao: 0.1,
          desc: "The windiest world, with gusts over 2,000 km/h. The farthest planet, it takes 165 years to orbit the Sun once." }
    ]
    readonly property var sunInfo: {
        "name": "Sun", "size": 3.5, "color": "#ffb12e",
        "meta": "a G-type star \u00b7 4.6 billion years old",
        "desc": "Our star holds 99.8% of the system's mass. Its light takes just over 8 minutes to reach Earth."
    }

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
        var pos = Qt.vector3d(0, 0, 0)
        if (i !== -2) {
            var o = rep.objectAt(i)
            if (!o) return null
            pos = o.bodyPos
        }
        var sp = view.mapFrom3DScene(pos)
        if (sp.z <= 0) return null
        var size = i === -2 ? sunInfo.size : planets[i].size
        var r = size * (height / 2) / (0.364 * (sp.z + cam.clipNear))
        return { x: sp.x, y: sp.y, r: r, reach: Math.max(26, r * 1.15) }
    }

    function hitTest(px, py) {
        var best = -1, bestScore = 1e9
        for (var i = -2; i < planets.length; i++) {
            if (i === -1) continue
            var t = screenOf(i)
            if (!t) continue
            var d = Math.hypot(t.x - px, t.y - py)
            if (d < t.reach && d / t.reach < bestScore) { bestScore = d / t.reach; best = i }
        }
        return best
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

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

        // soft light in the hovered body's colour; it lights its neighbours (moon, rocks, nearby planets)
        PointLight {
            id: hoverLight
            color: "white"
            brightness: 0
            constantFade: 1
            linearFade: 0
            quadraticFade: 0.12
        }

        // sun: textured core plus a few translucent shells for a soft glow
        Node {
            id: sun
            property real glow: root.hovered === -2 ? 1 : 0
            Behavior on glow { NumberAnimation { duration: 160 } }
            Model {
                property int planetIndex: -2
                source: "#Sphere"
                scale: Qt.vector3d(0.07, 0.07, 0.07)
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
                    scale: Qt.vector3d(modelData.s, modelData.s, modelData.s)
                    opacity: modelData.o * (1 + 1.8 * sun.glow)
                    depthBias: modelData.b
                    pickable: false
                    materials: DefaultMaterial {
                        lighting: DefaultMaterial.NoLighting
                        diffuseColor: "#ffa23a"
                    }
                }
            }
        }

        DefaultMaterial { id: dashMat; lighting: DefaultMaterial.NoLighting; diffuseColor: "#f3e6c4" }

        // asteroid belt between Mars and Jupiter: tiny cubes sharing one material
        PrincipledMaterial { id: rockMat; baseColor: "#c4a67e"; roughness: 1; specularAmount: 0; emissiveFactor: Qt.vector3d(0.16, 0.12, 0.08) }
        Node {
            NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 400000; loops: Animation.Infinite }
            Repeater3D {
                model: 260
                Model {
                    property real a: Math.random() * Math.PI * 2
                    property real r: 22.5 + (Math.random() + Math.random() - 1) * 1.8
                    property real e: 0.0008 + Math.random() * 0.0016
                    source: "#Cube"
                    position: Qt.vector3d(Math.cos(a) * r, (Math.random() - 0.5) * 0.5, Math.sin(a) * r)
                    eulerRotation: Qt.vector3d(Math.random() * 360, Math.random() * 360, 0)
                    scale: Qt.vector3d(e, e, e)
                    pickable: false
                    materials: [ rockMat ]
                }
            }
        }

        Repeater3D {
            id: rep
            model: root.planets
            Node {
                id: orbit
                required property var modelData
                required property int index
                readonly property vector3d bodyPos: body.scenePosition
                property real glow: root.hovered === orbit.index ? 1 : 0
                readonly property color tint: modelData.color
                Behavior on glow { NumberAnimation { duration: 160 } }
                Texture {
                    id: bodyTex
                    source: root.tex(orbit.modelData.tex)
                    generateMipmaps: true; mipFilter: Texture.Linear
                }
                Texture {
                    id: bodyNormal
                    source: orbit.modelData.normal !== undefined ? root.tex(orbit.modelData.normal) : ""
                    generateMipmaps: true; mipFilter: Texture.Linear
                }
                Texture { id: moonNormal; source: root.tex("moon_n.png"); generateMipmaps: true; mipFilter: Texture.Linear }

                NumberAnimation on eulerRotation.y {
                    from: orbit.index * 47
                    to: orbit.index * 47 + 360
                    duration: 40000 * Math.pow(orbit.modelData.year, 0.7)
                    loops: Animation.Infinite
                }

                // orbit ring: short flat dashes of constant length and width, so they stay sharp at any angle
                Node {
                    opacity: root.hovered === orbit.index || root.selected === orbit.index ? 0.7 : 0.3
                    Repeater3D {
                        model: Math.round(2 * Math.PI * orbit.modelData.dist / 2.5)
                        Model {
                            required property int index
                            readonly property real ang: index * 2 * Math.PI / Math.round(2 * Math.PI * orbit.modelData.dist / 2.5)
                            source: "#Cube"
                            position: Qt.vector3d(Math.cos(ang) * orbit.modelData.dist, 0, Math.sin(ang) * orbit.modelData.dist)
                            eulerRotation.y: -ang * 180 / Math.PI - 90
                            scale: Qt.vector3d(0.015, 0.0004, 0.0016)
                            pickable: false
                            materials: [ dashMat ]
                        }
                    }
                }

                Node {
                    id: body
                    x: orbit.modelData.dist
                    // axial tilt, then spin around the tilted axis
                    Node {
                        eulerRotation.z: orbit.modelData.tilt
                        Model {
                            property int planetIndex: orbit.index
                            readonly property real sc: orbit.modelData.size * 0.02
                            source: "#Sphere"
                            scale: Qt.vector3d(sc, sc * (orbit.modelData.flat !== undefined ? orbit.modelData.flat : 1), sc)
                            pickable: true
                            materials: PrincipledMaterial {
                                baseColorMap: bodyTex
                                emissiveMap: bodyTex
                                emissiveFactor: Qt.vector3d(orbit.tint.r * orbit.glow * 0.4, orbit.tint.g * orbit.glow * 0.4, orbit.tint.b * orbit.glow * 0.4)
                                normalMap: orbit.modelData.normal !== undefined ? bodyNormal : null
                                normalStrength: 0.9
                                roughness: 1
                                metalness: 0
                                specularAmount: 0
                            }
                            NumberAnimation on eulerRotation.y {
                                from: 0; to: orbit.modelData.spin > 0 ? 360 : -360
                                duration: Math.abs(orbit.modelData.spin) * 1000
                                loops: Animation.Infinite
                            }
                        }
                        // earth: clouds + thin atmosphere
                        Model {
                            visible: orbit.modelData.clouds === true
                            readonly property real sc: orbit.modelData.size * 0.0203
                            source: "#Sphere"
                            scale: Qt.vector3d(sc, sc, sc)
                            pickable: false
                            materials: PrincipledMaterial {
                                baseColor: "white"
                                roughness: 1
                                opacityMap: Texture { source: root.tex("2k_earth_clouds.jpg"); generateMipmaps: true; mipFilter: Texture.Linear }
                                opacityChannel: Material.R
                            }
                            NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 34000; loops: Animation.Infinite }
                        }
                        Model {
                            visible: orbit.modelData.atmo !== undefined
                            readonly property real sc: orbit.modelData.size * 0.0207
                            source: "#Sphere"
                            scale: Qt.vector3d(sc, sc, sc)
                            opacity: orbit.modelData.ao !== undefined ? orbit.modelData.ao : 0
                            depthBias: -1   // same centre as the clouds: pin the draw order so the blend can't flip
                            pickable: false
                            materials: DefaultMaterial {
                                lighting: DefaultMaterial.NoLighting
                                diffuseColor: orbit.modelData.atmo !== undefined ? orbit.modelData.atmo : "white"
                            }
                        }
                        // hover halo in the planet's own colour
                        Repeater3D {
                            model: [ { k: 0.0245, o: 0.2, b: -3 }, { k: 0.031, o: 0.07, b: -4 } ]
                            Model {
                                required property var modelData
                                visible: orbit.glow > 0.01
                                readonly property real sc: orbit.modelData.size * modelData.k
                                source: "#Sphere"
                                scale: Qt.vector3d(sc, sc, sc)
                                opacity: modelData.o * orbit.glow
                                depthBias: modelData.b
                                pickable: false
                                materials: DefaultMaterial {
                                    lighting: DefaultMaterial.NoLighting
                                    diffuseColor: orbit.modelData.color
                                }
                            }
                        }
                        // saturn's rings, in the planet's equatorial plane
                        Model {
                            visible: orbit.modelData.rings === true
                            source: "#Rectangle"
                            eulerRotation.x: -90
                            scale: Qt.vector3d(orbit.modelData.size * 0.0454, orbit.modelData.size * 0.0454, 1)
                            pickable: false
                            materials: DefaultMaterial {
                                lighting: DefaultMaterial.NoLighting
                                cullMode: Material.NoCulling
                                diffuseMap: Texture { source: root.tex("saturn_ring.png"); generateMipmaps: true; mipFilter: Texture.Linear }
                            }
                        }
                    }
                    // the moon
                    Node {
                        visible: orbit.modelData.moon === true
                        NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 25000; loops: Animation.Infinite }
                        Model {
                            x: 2.1
                            source: "#Sphere"
                            scale: Qt.vector3d(0.0075, 0.0075, 0.0075)
                            pickable: false
                            materials: PrincipledMaterial {
                                baseColorMap: Texture { source: root.tex("2k_moon.jpg"); generateMipmaps: true; mipFilter: Texture.Linear }
                                normalMap: moonNormal
                                normalStrength: 0.9
                                roughness: 1
                                specularAmount: 0
                            }
                        }
                    }
                }
            }
        }

        // glide the camera pivot toward the selected body (or back to the centre)
        FrameAnimation {
            running: true
            onTriggered: {
                var t = Qt.vector3d(0, 0, 0)
                if (root.selected >= 0) {
                    var o = rep.objectAt(root.selected)
                    if (o) t = o.bodyPos
                }
                var hv = root.hovered
                if (hv >= 0) {
                    var ho = rep.objectAt(hv)
                    if (ho) { hoverLight.position = ho.bodyPos; hoverLight.color = root.planets[hv].color }
                } else if (hv === -2) {
                    hoverLight.position = Qt.vector3d(0, 0, 0); hoverLight.color = root.sunInfo.color
                }
                hoverLight.brightness += ((hv !== -1 ? 3.5 : 0) - hoverLight.brightness) * Math.min(1, frameTime * 10)
                var k = Math.min(1, frameTime * 5)
                origin.position = Qt.vector3d(
                    origin.position.x + (t.x - origin.position.x) * k,
                    origin.position.y + (t.y - origin.position.y) * k,
                    origin.position.z + (t.z - origin.position.z) * k)
            }
        }
    }

    NumberAnimation { id: zoomAnim; target: cam; property: "z"; duration: 900; easing.type: Easing.InOutCubic }

    // click a body to zoom in on it; click it again (or empty space) to return to the overview
    function select(i) {
        introZoom.stop()
        if (i === selected) i = -1
        selected = i
        zoomAnim.stop()
        zoomAnim.to = i === -2 ? sunInfo.size * 5 + 6 : i >= 0 ? planets[i].size * 5 + 5 : homeZ
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
            root.select(root.hitTest(p.x, p.y))
        }
    }

    HoverHandler {
        id: hover
        cursorShape: root.hovered !== -1 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPointChanged: root.hoverPos = point.position
        onHoveredChanged: if (!hovered) root.hovered = -1
    }
    // re-test every frame so the hover ring tracks planets moving under a still cursor
    FrameAnimation {
        running: hover.hovered
        onTriggered: {
            root.hovered = root.hitTest(root.hoverPos.x, root.hoverPos.y)
            var t = root.hovered !== -1 ? root.screenOf(root.hovered) : null
            if (t) { root.ringX = t.x; root.ringY = t.y; root.ringR = Math.max(16, t.r * 1.25 + 5) }
        }
    }

    // tooltip card next to the hovered body
    property int tipIndex: -1
    onHoveredChanged: if (hovered !== -1) tipIndex = hovered
    readonly property var tipInfo: tipIndex === -2 ? sunInfo : tipIndex >= 0 ? planets[tipIndex] : null

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
        opacity: root.hovered !== -1 ? 0.95 : 0
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
    onUnlockingChanged: if (unlocking) { fadeIn.stop(); fadeOut.start() }

    Keys.onPressed: event => {
        if (root.busy || root.unlocking) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (password.length > 0) { root.submit(password); password = "" }
        } else if (event.key === Qt.Key_Backspace) {
            password = password.slice(0, -1)
        } else if (event.key === Qt.Key_Escape) {
            password = ""
        } else if (event.text.length === 1 && event.text >= " ") {
            root.edited()
            password += event.text
        }
    }
}
