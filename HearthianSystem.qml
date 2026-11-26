import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils

// The Hearthian System theme. The planets are meshes made by tools/make_hearthian_meshes.py (models/generated/);
// models placed in models/ow/ are used instead; with neither, simple primitives stand in.
// The effects (sand column, cyclones, fog, black hole, comet tail) are always drawn here.
// Scene.qml loads one theme at a time and talks to it through `planets`, `sunInfo`, `moonInfo` and bodyPos().
Node {
    id: system
    required property Item scene
    readonly property string title: "Hearthian System"
    readonly property real homeZ: 100            // a smaller system than the solar one: bring the camera closer

    // indices into `planets`; the Quantum Moon (10) can orbit any of `qmHosts`
    readonly property var names: ["Sun Station", "the Hourglass Twins", "Timber Hearth", "Attlerock", "Brittle Hollow",
                                  "Hollow's Lantern", "Giant's Deep", "Orbital Probe Cannon", "Dark Bramble", "the Interloper", "Quantum Moon"]
    readonly property var qmHosts: [1, 2, 4, 6, 8]
    readonly property var qmRadius: ({ 1: 4.2, 2: 3.6, 4: 3.9, 6: 5.8, 8: 4.4 })
    property int qmHost: qmHosts[Math.floor(Math.random() * qmHosts.length)]
    property real qmAngle: Math.random() * Math.PI * 2
    property bool qmSeen: false

    // size = body radius in scene units (the Sun is 3.5); `solid: false` = does not hide what is behind it
    readonly property var planets: [
        { name: "Sun Station", size: 0.45, color: "#d9b36b", meta: "a station on a tight orbit around the Sun",
          desc: "An outpost skimming just above the Sun. Whoever built it wanted a very close look at the star, and at what it might do next." },
        { name: "Hourglass Twins", size: 2.4, color: "#d9a066", solid: false, meta: "Ash Twin and Ember Twin · two worlds circling each other",
          desc: "Two planets so close that sand pours from one to the other in a steady column, slowly burying one and uncovering the other." },
        { name: "Timber Hearth", size: 1.3, color: "#6f9a48", meta: "a home world of forests and geysers · one small moon",
          desc: "A green, mountainous world with a little village in a crater. Every journey across the system starts here." },
        { name: "Attlerock", size: 0.38, color: "#a39e96", meta: "moon of Timber Hearth",
          desc: "A small, cratered moon close to home, and the first trip for a lot of new pilots." },
        { name: "Brittle Hollow", size: 1.45, color: "#8a76a3", meta: "a hollow world · a black hole at its core",
          desc: "Its crust is a thin shell around a black hole. Pieces break off and fall inward, so the ground may not be there tomorrow." },
        { name: "Hollow's Lantern", size: 0.4, color: "#ffb347", meta: "volcanic moon of Brittle Hollow",
          desc: "A glowing moon covered in volcanoes. It keeps hurling molten rock at its fragile neighbour." },
        { name: "Giant's Deep", size: 2.7, color: "#2f8f8a", meta: "an ocean world under endless storms",
          desc: "A deep ocean wrapped in wild weather. Cyclones roam its surface, strong enough to throw whole islands into the sky." },
        { name: "Orbital Probe Cannon", size: 0.5, color: "#9aa6c4", meta: "in orbit around Giant's Deep",
          desc: "An ancient cannon built to fire probes across space. Something has left it battered and broken." },
        { name: "Dark Bramble", size: 2.2, color: "#c8d8cf", meta: "a tangle of vines in a ball of fog",
          desc: "Giant thorny vines wrapped in pale fog. Travellers say there is far more room inside than there should be." },
        { name: "The Interloper", size: 0.6, color: "#bfe6ff", meta: "an icy comet on a long, stretched orbit",
          desc: "A frozen comet that dives close to the Sun and swings far out again. Near the Sun its ice boils off into a long tail." },
        { name: "Quantum Moon", size: 0.55, color: "#9b93c9", meta: "orbiting " + names[qmHost] + " (for now)",
          desc: "It only moves when nobody is watching. Look away, and it may be orbiting a different world when you look back." }
    ]
    readonly property var sunInfo: {
        "name": "Sun", "size": 3.5, "color": "#ffb12e",
        "meta": "an old star near the end of its life",
        "desc": "The star at the centre of this small system. Every 22 minutes, something happens to it."
    }
    readonly property var moonInfo: null

    readonly property var targets: [station, twins, hearth, attle, hollow, lantern, deep, cannon, bramble, comet, qm]
    function bodyPos(i) { var n = targets[i]; return n ? n.scenePosition : null }

    // ---- building blocks ------------------------------------------------------------------------------------
    // a lit sphere of radius r
    component Ball: Model {
        id: ball
        property real r: 1
        property color col: "white"
        property real shine: 0          // emissive strength, for bodies that glow by themselves
        source: "#Sphere"
        pickable: false
        scale: Qt.vector3d(ball.r * 0.02, ball.r * 0.02, ball.r * 0.02)
        materials: PrincipledMaterial {
            baseColor: ball.col
            emissiveFactor: Qt.vector3d(ball.col.r * ball.shine, ball.col.g * ball.shine, ball.col.b * ball.shine)
            roughness: 1; metalness: 0; specularAmount: 0
        }
    }
    // an unlit, see-through sphere (fog, atmospheres, comet tail); set opacity where it is used
    component Haze: Model {
        id: haze
        property real r: 1
        property color col: "white"
        source: "#Sphere"
        pickable: false
        scale: Qt.vector3d(haze.r * 0.02, haze.r * 0.02, haze.r * 0.02)
        materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; diffuseColor: haze.col }
    }
    // a lit box, size in scene units
    component Box: Model {
        id: box
        property vector3d size: Qt.vector3d(1, 1, 1)
        property color col: "grey"
        source: "#Cube"
        pickable: false
        scale: box.size.times(0.01)
        materials: PrincipledMaterial { baseColor: box.col; roughness: 0.8; metalness: 0.2; specularAmount: 0.2 }
    }
    // a planet mesh scaled to radius r: the user's own models/ow/<name>.glb, else models/generated/<name>.glb;
    // `ok` is false when neither loads, and the primitives next to it are shown instead
    component Mesh: Node {
        id: mesh
        property string name
        property real r: 1
        property int stage: 0
        readonly property bool ok: loader.status === RuntimeLoader.Success
        scale: Qt.vector3d(mesh.r, mesh.r, mesh.r)
        RuntimeLoader {
            id: loader
            source: mesh.stage === 0 ? Qt.resolvedUrl("models/ow/" + mesh.name + ".glb")
                  : mesh.stage === 1 ? Qt.resolvedUrl("models/generated/" + mesh.name + ".glb") : ""
            onStatusChanged: if (status === RuntimeLoader.Error && mesh.stage < 2) mesh.stage++
        }
    }
    // a body that can be hovered: soft halo in its own colour while hovered
    component Body: Node {
        id: body
        required property Item scene
        property int idx: -1
        property real r: 1
        property color col: "white"
        property real glow: body.scene.hovered === body.idx ? 1 : 0
        Behavior on glow { NumberAnimation { duration: 160 } }
        Haze { visible: body.glow > 0.01; r: body.r * 1.3; col: body.col; opacity: 0.18 * body.glow; depthBias: -3 }
    }
    // a node that turns around its parent once per `period` ms
    component Revolve: Node {
        id: rv
        property real period: 30000
        property real phase: 0
        NumberAnimation on eulerRotation.y { from: rv.phase; to: rv.phase + 360; duration: rv.period; loops: Animation.Infinite }
    }
    // dashed orbit, like the solar theme's: a circle, or an ellipse with the Sun at a focus (c = focus offset)
    component Orbit: Node {
        id: orb
        required property Item scene
        property int idx: -1
        property real a: 10
        property real b: a
        property real c: 0
        readonly property int n: Math.round(2 * Math.PI * Math.sqrt((a * a + b * b) / 2) / 2.5)
        opacity: (scene.hovered === idx || scene.selected === idx ? 0.7 : 0.3) * (1 - 0.9 * scene.space)
        DefaultMaterial { id: dash; lighting: DefaultMaterial.NoLighting; diffuseColor: "#f3e6c4" }
        Repeater3D {
            model: orb.n
            Model {
                required property int index
                readonly property real t: index * 2 * Math.PI / orb.n
                source: "#Cube"
                position: Qt.vector3d(orb.a * Math.cos(t) - orb.c, 0, orb.b * Math.sin(t))
                eulerRotation.y: -Math.atan2(orb.b * Math.cos(t), -orb.a * Math.sin(t)) * 180 / Math.PI   // along the orbit
                scale: Qt.vector3d(0.015, 0.0004, 0.0016)
                pickable: false
                materials: [ dash ]
            }
        }
    }

    // ---- orbits ---------------------------------------------------------------------------------------------
    Orbit { scene: system.scene; idx: 0; a: 5.2 }
    Orbit { scene: system.scene; idx: 1; a: 9.5 }
    Orbit { scene: system.scene; idx: 2; a: 14 }
    Orbit { scene: system.scene; idx: 4; a: 19.5 }
    Orbit { scene: system.scene; idx: 6; a: 27 }
    Orbit { scene: system.scene; idx: 8; a: 36 }

    // ---- Sun Station: a small station skimming the Sun -----------------------------------------------------
    Revolve {
        period: 9000; phase: 30
        Body {
            id: station
            scene: system.scene; idx: 0; r: 0.45; col: "#d9b36b"
            x: 5.2
            Node {
                eulerRotation.z: 90                               // tilt in its own node, spin inside it (Qt applies yaw last)
                Node {
                    NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 7000; loops: Animation.Infinite }
                    Mesh { id: stationMesh; name: "sun_station"; r: 0.55 }
                    Node {
                        visible: !stationMesh.ok
                        Box { size: Qt.vector3d(0.22, 0.9, 0.22); col: "#a39a8a" }
                        Box { size: Qt.vector3d(0.7, 0.05, 0.3); col: "#5c6b8c"; x: 0.5 }
                        Box { size: Qt.vector3d(0.7, 0.05, 0.3); col: "#5c6b8c"; x: -0.5 }
                        Ball { r: 0.16; col: "#ffd08a"; shine: 0.8; y: 0.5 }
                    }
                }
            }
        }
    }

    // ---- the Hourglass Twins: two planets circling each other, a column of sand between them -------------
    Revolve {
        period: 30000; phase: 200
        Body {
            id: twins
            scene: system.scene; idx: 1; r: 2.4; col: "#d9a066"
            x: 9.5
            Node {
                id: pair
                property real flow: 0
                NumberAnimation on flow { from: 0; to: 1; duration: 2400; loops: Animation.Infinite }
                NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 14000; loops: Animation.Infinite }
                Mesh { id: ashMesh; name: "ash_twin"; r: 0.9; x: 1.5 }      // Ash Twin
                Mesh { id: emberMesh; name: "ember_twin"; r: 0.95; x: -1.5 } // Ember Twin
                Ball { r: ashMesh.ok ? 0.68 : 0.9; col: "#d9a066"; x: 1.5 }        // the real models lack the sand: keep a smaller ball
                Ball { r: emberMesh.ok ? 0.55 : 0.95; col: emberMesh.ok ? "#d9a066" : "#b35a3c"; x: -1.5 }
                Model {                                           // the sand column
                    source: "#Cylinder"
                    pickable: false
                    eulerRotation.z: 90
                    scale: Qt.vector3d(0.0022, 0.03, 0.0022)
                    opacity: 0.55
                    materials: PrincipledMaterial { baseColor: "#e3b778"; emissiveFactor: Qt.vector3d(0.25, 0.18, 0.1); roughness: 1; specularAmount: 0 }
                }
                Repeater3D {                                      // grains pouring from Ash Twin to Ember Twin
                    model: 10
                    Box {
                        required property int index
                        readonly property real f: (pair.flow + index / 10) % 1
                        size: Qt.vector3d(0.09, 0.09, 0.09); col: "#f0c890"
                        x: 0.6 - f * 1.15
                        y: Math.sin(f * Math.PI * 4 + index) * 0.05
                        z: Math.cos(f * Math.PI * 4 + index) * 0.05
                    }
                }
            }
        }
    }

    // ---- Timber Hearth and the Attlerock -------------------------------------------------------------------
    Revolve {
        period: 48000; phase: 100
        Body {
            id: hearth
            scene: system.scene; idx: 2; r: 1.3; col: "#6f9a48"
            x: 14
            Node {
                eulerRotation.z: 12
                Node {
                    NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 40000; loops: Animation.Infinite }
                    Mesh { id: hearthMesh; name: "timber_hearth"; r: 1.3 }
                    Ball { visible: !hearthMesh.ok; r: 1.3; col: "#6f9a48" }
                    Repeater3D {                                      // mountains and the crater rim
                        model: hearthMesh.ok ? 0 : 9
                        Node {
                            required property int index
                            eulerRotation: Qt.vector3d(Math.acos(1 - 2 * (index + 0.5) / 9) * 180 / Math.PI, index * 137.5, 0)
                            Ball { r: 0.32 + (index % 3) * 0.08; col: index % 2 ? "#7d6a52" : "#4f7a36"; y: 1.15; scale: Qt.vector3d(r * 0.02, r * 0.013, r * 0.02) }
                        }
                    }
                }
            }
            Haze { r: 1.4; col: "#9fd4ff"; opacity: 0.12; depthBias: -1 }
            Revolve {
                period: 14000
                Body {
                    id: attle
                    scene: system.scene; idx: 3; r: 0.38; col: "#a39e96"
                    x: 2.6
                    Mesh { id: attleMesh; name: "attlerock"; r: 0.38 }
                    Ball { visible: !attleMesh.ok; r: 0.38; col: "#a39e96" }
                }
            }
        }
    }

    // ---- Brittle Hollow: a cracked shell around a black hole, and Hollow's Lantern -------------------------
    Revolve {
        period: 62000; phase: 290
        Body {
            id: hollow
            scene: system.scene; idx: 4; r: 1.45; col: "#8a76a3"
            x: 19.5
            Node {
                NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 50000; loops: Animation.Infinite }
                Model {                                           // the black hole
                    source: "#Sphere"; pickable: false
                    scale: Qt.vector3d(0.007, 0.007, 0.007)
                    materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; diffuseColor: "black" }
                }
                Node {                                            // a thin ring of glowing matter around it
                    eulerRotation.x: 70
                    Node {
                        NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 3000; loops: Animation.Infinite }
                        Repeater3D {
                            model: 24
                            Model {
                                required property int index
                                source: "#Cube"; pickable: false
                                scale: Qt.vector3d(0.0008, 0.0002, 0.0008)
                                x: Math.cos(index / 24 * 2 * Math.PI) * 0.55
                                z: Math.sin(index / 24 * 2 * Math.PI) * 0.55
                                materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; diffuseColor: "#ffb062" }
                            }
                        }
                    }
                }
                Mesh { id: hollowMesh; name: "brittle_hollow"; r: 1.45 }
                Repeater3D {                                      // fallback crust: plates with gaps; a few break off and fall in
                    model: 34
                    Node {
                        id: plate
                        required property int index
                        readonly property bool falls: index % 9 === 4 && !hollowMesh.ok
                        visible: !hollowMesh.ok
                        property real k: 0                        // 0 = in place, 1 = swallowed
                        property real appear: 1
                        eulerRotation: Qt.vector3d(Math.acos(1 - 2 * (index + 0.5) / 34) * 180 / Math.PI, index * 137.5, 0)
                        Box {
                            size: Qt.vector3d(0.62, 0.12, 0.62); col: plate.index % 3 ? "#6b5b7a" : "#7f7086"
                            y: 1.4 - 1.05 * plate.k
                            opacity: (1 - plate.k) * plate.appear
                        }
                        SequentialAnimation {
                            running: plate.falls
                            loops: Animation.Infinite
                            ScriptAction { script: { plate.k = 0; plate.appear = 0 } }
                            NumberAnimation { target: plate; property: "appear"; to: 1; duration: 2000 }
                            PauseAnimation { duration: 3000 + plate.index * 700 }
                            NumberAnimation { target: plate; property: "k"; to: 1; duration: 6000; easing.type: Easing.InQuad }
                        }
                    }
                }
            }
            Revolve {
                period: 11000
                Body {
                    id: lantern
                    scene: system.scene; idx: 5; r: 0.4; col: "#ffb347"
                    x: 2.8
                    Mesh { id: lanternMesh; name: "hollows_lantern"; r: 0.4 }
                    Ball { visible: !lanternMesh.ok; r: 0.4; col: "#ffb347"; shine: 0.9 }
                    Haze { r: 0.55; col: "#ffb347"; opacity: 0.2; depthBias: -1 }   // its glow
                }
            }
        }
    }

    // ---- Giant's Deep: an ocean world with cyclones, and the Orbital Probe Cannon -------------------------
    Revolve {
        period: 80000; phase: 160
        Body {
            id: deep
            scene: system.scene; idx: 6; r: 2.7; col: "#2f8f8a"
            x: 27
            Node {
                NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 70000; loops: Animation.Infinite }
                Mesh { id: deepMesh; name: "giants_deep"; r: 2.7 }
                Ball { visible: !deepMesh.ok; r: 2.7; col: "#2f8f8a" }
                Repeater3D {                                      // cyclones: spinning white arms on the surface
                    model: deepMesh.ok && deepMesh.stage === 0 ? 0 : 6   // under the real model's cloud deck they show as dark smudges
                    Node {
                        required property int index
                        eulerRotation: Qt.vector3d(Math.acos(1 - 2 * (index + 0.5) / 6) * 180 / Math.PI, index * 137.5, 0)
                        Node {
                            y: 2.66
                            NumberAnimation on eulerRotation.y { from: 0; to: -360; duration: 2500 + index * 400; loops: Animation.Infinite }
                            Repeater3D {
                                model: 3
                                Box {
                                    required property int index
                                    eulerRotation.y: index * 60
                                    size: Qt.vector3d(1.1, 0.03, 0.14); col: "white"
                                    opacity: 0.55
                                }
                            }
                        }
                    }
                }
            }
            Haze { r: 2.95; col: "#8fe0d2"; opacity: 0.16; depthBias: -1 }
            Revolve {
                period: 20000
                Body {
                    id: cannon
                    scene: system.scene; idx: 7; r: 0.5; col: "#9aa6c4"
                    x: 4.6
                    Mesh { id: cannonMesh; name: "orbital_probe_cannon"; r: 0.7; eulerRotation: Qt.vector3d(20, 0, 70) }
                    Node {
                        visible: !cannonMesh.ok
                        eulerRotation: Qt.vector3d(20, 0, 70)
                        Box { size: Qt.vector3d(0.4, 0.4, 0.4); col: "#6e6a73" }
                        Model {
                            source: "#Cylinder"; pickable: false
                            y: 0.5
                            scale: Qt.vector3d(0.0024, 0.009, 0.0024)
                            materials: PrincipledMaterial { baseColor: "#827d88"; roughness: 0.7; metalness: 0.3 }
                        }
                        Ball { r: 0.08; col: "#9ad1ff"; shine: 1; y: -0.28 }
                    }
                }
            }
        }
    }

    // ---- Dark Bramble: thorny vines poking out of pale fog --------------------------------------------------
    Revolve {
        period: 100000; phase: 60
        Body {
            id: bramble
            scene: system.scene; idx: 8; r: 2.2; col: "#c8d8cf"
            x: 36
            Node {
                NumberAnimation on eulerRotation.y { from: 0; to: 360; duration: 90000; loops: Animation.Infinite }
                Mesh { id: brambleMesh; name: "dark_bramble"; r: 2.2 }
                Ball { visible: !brambleMesh.ok; r: 1.1; col: "#2c3a2e" }
                Repeater3D {
                    model: brambleMesh.ok ? 0 : 8
                    Node {
                        required property int index
                        eulerRotation: Qt.vector3d(Math.acos(1 - 2 * (index + 0.5) / 8) * 180 / Math.PI, index * 137.5, 0)
                        Model {                                   // a vine
                            source: "#Cylinder"; pickable: false
                            y: 1.6
                            scale: Qt.vector3d(0.0036, 0.026, 0.0036)
                            materials: PrincipledMaterial { baseColor: "#3b2f28"; roughness: 1; specularAmount: 0 }
                        }
                        Repeater3D {                              // thorns along it
                            model: 3
                            Model {
                                required property int index
                                source: "#Cylinder"; pickable: false
                                y: 1.5 + index * 0.55
                                eulerRotation: Qt.vector3d(0, index * 120, 60)
                                scale: Qt.vector3d(0.0012, 0.006, 0.0012)
                                materials: PrincipledMaterial { baseColor: "#4a3a30"; roughness: 1; specularAmount: 0 }
                            }
                        }
                    }
                }
            }
            Haze { r: brambleMesh.ok ? 1.5 : 2.2; col: "#dfe9e4"; opacity: 0.35; depthBias: -1 }   // the vine tips poke out of the fog
        }
    }

    // ---- the Interloper: an icy comet on a stretched, tilted orbit; fast near the Sun, slow far out ---------
    Node {
        eulerRotation: Qt.vector3d(9, 40, 0)
        Orbit { scene: system.scene; idx: 9; a: 31; b: 17; c: 25.9 }
        Body {
            id: comet
            scene: system.scene; idx: 9; r: 0.6; col: "#bfe6ff"
            property real m: 0                                    // mean anomaly: grows evenly with time (Kepler)
            NumberAnimation on m { from: 0; to: 2 * Math.PI; duration: 70000; loops: Animation.Infinite }
            readonly property real ea: {                          // eccentric anomaly, solved from m by Newton's method
                var e = 25.9 / 31, E = m < Math.PI ? m + e / 2 : m - e / 2
                for (var k = 0; k < 8; k++) E -= (E - e * Math.sin(E) - m) / (1 - e * Math.cos(E))
                return E
            }
            readonly property real dist: position.length()
            position: Qt.vector3d(31 * Math.cos(ea) - 25.9, 0, 17 * Math.sin(ea))
            Ball { visible: !cometMesh.ok; r: 0.6; col: "#cfe8f2"; shine: 0.15 }
            Node {                                                // the tail points away from the Sun and grows near it
                id: tail
                eulerRotation.y: -Math.atan2(comet.position.z, comet.position.x) * 180 / Math.PI
                readonly property real len: Math.max(1, Math.min(8, 60 / comet.dist))
                Mesh { id: cometMesh; name: "interloper"; r: 0.6 }   // its icy spikes point along +X: away from the Sun
                Repeater3D {
                    model: 3
                    Model {
                        required property int index
                        readonly property real l: tail.len * (1 - index * 0.25)
                        source: "#Sphere"; pickable: false
                        x: 0.3 + l / 2
                        scale: Qt.vector3d(l / 100, (0.9 - index * 0.25) / 100, (0.9 - index * 0.25) / 100)
                        opacity: (0.22 - index * 0.05) * Math.min(1, 14 / comet.dist)
                        depthBias: -2 - index
                        materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; diffuseColor: "#bfe6ff" }
                    }
                }
            }
        }
    }

    // ---- the Quantum Moon ------------------------------------------------------------------------------------
    // It only moves while unobserved: when it is off screen, hidden behind a nearer body, or the screen is dark
    // (lock fade-in, theme switch, after the supernova). Hovered or selected, it never moves.
    Body {
        id: qm
        scene: system.scene; idx: 10; r: 0.55; col: "#9b93c9"
        Mesh { id: qmMesh; name: "quantum_moon"; r: 0.55 }
        Ball { visible: !qmMesh.ok; r: 0.55; col: "#8d86a8" }
        Haze { r: 0.78; col: "#d8d4ff"; opacity: 0.22; depthBias: -1 }
    }
    function qmObserved() {
        var s = scene
        if (s.hovered === 10 || s.selected === 10) return true
        if (s.blackout) return false
        var t = s.screenOf(10)
        if (!t) return false
        if (t.x + t.r < 0 || t.x - t.r > s.width || t.y + t.r < 0 || t.y - t.r > s.height) return false
        for (var i = -2; i < planets.length; i++) {                 // hidden behind a nearer, solid body (the Sun included)?
            if (i === -1 || i === 10 || (i >= 0 && planets[i].solid === false)) continue
            var o = s.screenOf(i)
            if (o && o.z < t.z && Math.hypot(o.x - t.x, o.y - t.y) + t.r * 0.5 < o.r) return false
        }
        return true
    }
    FrameAnimation {
        running: true
        onTriggered: {
            system.qmAngle += frameTime * 0.35
            var h = system.bodyPos(system.qmHost)
            if (!h) return
            var R = system.qmRadius[system.qmHost]
            qm.position = h.plus(Qt.vector3d(Math.cos(system.qmAngle) * R, 0.4, Math.sin(system.qmAngle) * R))
            var seen = system.qmObserved()
            if (system.qmSeen && !seen) {                         // the moment nobody is looking, it jumps
                var others = system.qmHosts.filter(x => x !== system.qmHost)
                system.qmHost = others[Math.floor(Math.random() * others.length)]
                system.qmAngle = Math.random() * Math.PI * 2
            }
            system.qmSeen = seen
        }
    }
}
