import QtQuick
import QtQuick3D

// The real Solar System theme: textured planets, Earth's Moon, the asteroid belt and dashed orbits.
// Scene.qml loads one theme at a time and talks to it through `planets`, `sunInfo`, `moonInfo` and bodyPos().
Node {
    id: system
    required property Item scene
    readonly property string title: "Solar System"

    // Collapse mode (used by the Black Hole theme, which puts a black hole where the Sun is): over the Scene's cycle the
    // orbits shrink, the planets speed up, are stretched by the hole's tides and swallowed, inner worlds first. Everything
    // is back at its normal orbit when the cycle restarts. `progress` runs 0..1 over the cycle (Scene.cycleP).
    property bool collapse: false
    property real horizonR: 1.2                       // the hole's radius: a planet is gone once it reaches it
    readonly property real progress: collapse ? scene.cycleP : 0
    readonly property var deaths: [0.30, 0.42, 0.54, 0.64, 0.76, 0.86, 0.93, 0.985]   // when each planet is swallowed (share of the cycle)
    signal swallowed(int index)

    // dist/size are artistic, not to scale. tilt = axial tilt (deg), spin = seconds per rotation (negative = retrograde)
    readonly property var planets: [
        { name: "Mercury", dist: 7,    size: 0.8,  tex: "2k_mercury.jpg", normal: "mercury_n.png", tilt: 0,   spin: 120, year: 0.24, au: 0.39, color: "#bda98f",
          desc: "The smallest planet and the closest to the Sun. A year here lasts just 88 days, yet a single day lasts 176 Earth days." },
        { name: "Venus",   dist: 10.5, size: 1.25, tex: "2k_venus_atmosphere.jpg", tilt: 177, spin: 200, year: 0.62, au: 0.72, color: "#e8c27c", atmo: "#ffe0a8", ao: 0.14,
          desc: "The hottest planet, around 465 \u00b0C under thick clouds of acid. It spins backwards, so the Sun rises in the west." },
        { name: "Earth",   dist: 15,   size: 1.35, tex: "2k_earth_daymap.jpg", night: true, tilt: 23,  spin: 40,  year: 1.0,  au: 1.0,  color: "#3a8cbd", clouds: true, moon: true, atmo: "#8cc4ff", ao: 0.12,
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

    // where a target is in the scene: 0..7 = planets, -3 = the Moon (null if it does not exist (any more))
    function bodyPos(i) {
        var o = rep.objectAt(i === -3 ? moonHost : i)
        if (!o || o.gone) return null
        return i === -3 ? o.moonPos : o.bodyPos
    }

    // collapse mode: the orbit radius of planet i. It stays near its normal value at first, then plunges to the hole
    // at the planet's moment (deaths[i]).
    function radiusOf(i) {
        var d = deaths[i]
        if (progress >= d) return 0
        return planets[i].dist * Math.pow(1 - Math.pow(progress / d, 2.4), 0.62)
    }

    DefaultMaterial { id: dashMat; lighting: DefaultMaterial.NoLighting; diffuseColor: "#f3e6c4" }

    // asteroid belt between Mars and Jupiter: tiny cubes sharing one material
    PrincipledMaterial { id: rockMat; baseColor: "#c4a67e"; roughness: 1; specularAmount: 0; emissiveFactor: Qt.vector3d(0.16, 0.12, 0.08) }
    Node {
        readonly property real k: system.collapse ? Math.max(0, 1 - Math.pow(system.progress / 0.72, 2)) : 1   // the belt is pulled in and thins out
        visible: k > 0.02
        scale: Qt.vector3d(k, 1, k)
        opacity: (1 - 0.9 * scene.space) * Math.min(1, k * 2)
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
        model: system.planets
        Node {
            id: orbit
            required property var modelData
            required property int index
            readonly property vector3d bodyPos: body.scenePosition
            readonly property vector3d moonPos: moonBody.scenePosition
            // collapse mode: where this planet is now (distance from the hole) and how much of it is left
            readonly property real r: system.collapse ? system.radiusOf(index) : modelData.dist
            readonly property real cap: system.horizonR + modelData.size * 0.5
            readonly property real fade: system.collapse ? Math.max(0, Math.min(1, (r - cap) / (cap * 1.2))) : 1   // 1 = whole, 0 = swallowed
            readonly property bool gone: system.collapse && fade <= 0.001
            onGoneChanged: if (gone) {
                system.swallowed(index)
                if (scene.selected === index || (scene.selected === -3 && modelData.moon === true)) scene.select(scene.selected)   // leave the zoom
            }
            property real moonGlow: scene.hovered === -3 && modelData.moon === true ? 1 : 0
            Behavior on moonGlow { NumberAnimation { duration: 160 } }
            property real glow: scene.hovered === orbit.index ? 1 : 0
            readonly property color tint: modelData.color
            Behavior on glow { NumberAnimation { duration: 160 } }
            Texture {
                id: bodyTex
                source: scene.tex(orbit.modelData.tex)
                generateMipmaps: true; mipFilter: Texture.Linear
            }
            Texture {
                id: bodyNormal
                source: orbit.modelData.normal !== undefined ? scene.tex(orbit.modelData.normal) : ""
                generateMipmaps: true; mipFilter: Texture.Linear
            }
            Texture { id: moonNormal; source: scene.tex("moon_n.png"); generateMipmaps: true; mipFilter: Texture.Linear }
            Texture { id: moonTex; source: scene.tex("2k_moon.jpg"); generateMipmaps: true; mipFilter: Texture.Linear }

            property real animAng: orbit.index * 47      // normal mode: a steady turn
            property real ang: orbit.index * 47          // collapse mode: turns faster as the orbit shrinks (Kepler: r^-1.5)
            eulerRotation.y: system.collapse ? ang : animAng
            NumberAnimation on animAng {
                running: !system.collapse
                from: orbit.index * 47
                to: orbit.index * 47 + 360
                duration: 40000 * Math.pow(orbit.modelData.year, 0.7)
                loops: Animation.Infinite
            }
            FrameAnimation {
                running: system.collapse && !orbit.gone
                onTriggered: orbit.ang += 360 * frameTime / (40 * Math.pow(orbit.modelData.year, 0.7)) * Math.min(14, Math.pow(orbit.modelData.dist / Math.max(orbit.r, 0.5), 1.5))
            }

            // orbit ring: short flat dashes of constant length and width, so they stay sharp at any angle
            Node {
                visible: !orbit.gone
                scale: system.collapse ? Qt.vector3d(Math.max(0.001, orbit.r / orbit.modelData.dist), 1, Math.max(0.001, orbit.r / orbit.modelData.dist)) : Qt.vector3d(1, 1, 1)
                opacity: (scene.hovered === orbit.index || scene.selected === orbit.index ? 0.7 : 0.3) * (1 - 0.9 * scene.space) * Math.min(1, orbit.fade * 3)
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
                x: orbit.r
                visible: !orbit.gone
                // tides: stretched along the line to the hole and shrunk away as it is swallowed
                scale: orbit.fade < 1 ? Qt.vector3d(Math.max(0.001, orbit.fade * (1 + 3.5 * (1 - orbit.fade))), Math.max(0.001, orbit.fade), Math.max(0.001, orbit.fade)) : Qt.vector3d(1, 1, 1)
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
                    // earth: city lights, visible only on the night side (a small shader: it needs the Sun's direction)
                    Model {
                        visible: orbit.modelData.night === true
                        readonly property real sc: orbit.modelData.size * 0.02015
                        source: "#Sphere"
                        scale: Qt.vector3d(sc, sc, sc)
                        depthBias: 1   // same centre as the clouds: pin the draw order (lights first) so the blend can't flip
                        pickable: false
                        materials: CustomMaterial {
                            sourceBlend: CustomMaterial.One
                            destinationBlend: CustomMaterial.One   // additive: black adds nothing
                            cullMode: Material.BackFaceCulling
                            fragmentShader: Qt.resolvedUrl("shaders/earth_night.frag")
                            property vector3d sunDir: body.scenePosition.times(-1).normalized()   // the Sun sits at the world origin
                            property real brightness: 1.5
                            property TextureInput nightMap: TextureInput {
                                texture: Texture { source: scene.tex("2k_earth_nightmap.jpg"); generateMipmaps: true; mipFilter: Texture.Linear }
                            }
                        }
                        NumberAnimation on eulerRotation.y { from: 0; to: orbit.modelData.spin > 0 ? 360 : -360; duration: Math.abs(orbit.modelData.spin) * 1000; loops: Animation.Infinite }   // same spin as the planet
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
                            opacityMap: Texture { source: scene.tex("2k_earth_clouds.jpg"); generateMipmaps: true; mipFilter: Texture.Linear }
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
                            diffuseMap: Texture { source: scene.tex("saturn_ring.png"); generateMipmaps: true; mipFilter: Texture.Linear }
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
}
