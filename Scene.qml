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
    property int selected: -1          // -2 = Sun, 0..7 = planets, -1 = none (overview)

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

    readonly property var moonInfo: {
        "name": "Moon", "size": 0.375, "color": "#c9c4b8",
        "meta": "orbits Earth every 27 days \u00b7 384,400 km away",
        "desc": "Earth's only natural satellite, about a quarter of its width. It drifts away from us by roughly 3.8 cm every year."
    }
    readonly property int moonHost: planets.findIndex(p => p.moon === true)   // the planet the Moon orbits
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
        var pos = Qt.vector3d(0, 0, 0)
        if (i === -3) {
            var h = rep.objectAt(moonHost)
            if (!h) return null
            pos = h.moonPos
        } else if (i !== -2) {
            var o = rep.objectAt(i)
            if (!o) return null
            pos = o.bodyPos
        }
        var sp = view.mapFrom3DScene(pos)
        if (sp.z <= 0) return null
        var size = i === -3 ? moonInfo.size : i === -2 ? sunInfo.size : planets[i].size
        var r = size * (height / 2) / (0.364 * (sp.z + cam.clipNear))
        return { x: sp.x, y: sp.y, r: r, reach: Math.max(i === -3 ? 14 : 26, r * 1.15) }
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

        DefaultMaterial { id: dashMat; lighting: DefaultMaterial.NoLighting; diffuseColor: "#f3e6c4" }

        // asteroid belt between Mars and Jupiter: tiny cubes sharing one material
        PrincipledMaterial { id: rockMat; baseColor: "#c4a67e"; roughness: 1; specularAmount: 0; emissiveFactor: Qt.vector3d(0.16, 0.12, 0.08) }
        Node {
            opacity: 1 - 0.9 * root.space
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
                readonly property vector3d moonPos: moonBody.scenePosition
                property real moonGlow: root.hovered === -3 && modelData.moon === true ? 1 : 0
                Behavior on moonGlow { NumberAnimation { duration: 160 } }
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
                Texture { id: moonTex; source: root.tex("2k_moon.jpg"); generateMipmaps: true; mipFilter: Texture.Linear }

                NumberAnimation on eulerRotation.y {
                    from: orbit.index * 47
                    to: orbit.index * 47 + 360
                    duration: 40000 * Math.pow(orbit.modelData.year, 0.7)
                    loops: Animation.Infinite
                }

                // orbit ring: short flat dashes of constant length and width, so they stay sharp at any angle
                Node {
                    opacity: (root.hovered === orbit.index || root.selected === orbit.index ? 0.7 : 0.3) * (1 - 0.9 * root.space)
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
                            id: moonBody
                            x: 2.1
                            source: "#Sphere"
                            scale: Qt.vector3d(0.0075, 0.0075, 0.0075)
                            pickable: false
                            materials: PrincipledMaterial {
                                baseColorMap: moonTex
                                emissiveMap: moonTex
                                emissiveFactor: Qt.vector3d(0.4 * orbit.moonGlow, 0.4 * orbit.moonGlow, 0.37 * orbit.moonGlow)
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
                } else if (root.selected === -3) {
                    var mo = rep.objectAt(root.moonHost)
                    if (mo) t = mo.moonPos
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
    Timer {
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
    onUnlockingChanged: if (unlocking) { novaAnim.stop(); resetNova(); fadeIn.stop(); fadeOut.start() }

    Keys.onPressed: event => {
        if (root.busy || root.unlocking) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (password.length > 0) { root.submit(password); password = "" }
        } else if (event.key === Qt.Key_Backspace) {
            password = (event.modifiers & Qt.ControlModifier) ? "" : password.slice(0, -1)   // Ctrl+Backspace clears everything
        } else if (event.key === Qt.Key_Escape) {
            if (root.selected !== -1) root.select(root.selected)   // Esc first leaves the zoom ...
            else password = ""                                     // ... and otherwise clears the password
        } else if (event.text.length === 1 && event.text >= " ") {
            root.edited()
            password += event.text
        }
    }
}
