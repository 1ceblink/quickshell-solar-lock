import QtQuick
import QtQuick3D

// The Black Hole theme: the Solar System with a black hole where the Sun was. Over each 22-minute cycle the planets slowly
// spiral into it, inner worlds first, and the hole grows and brightens with every one it swallows. When the last is gone
// the hole explodes (the Scene's supernova plays here) and everything starts again. The planets are SolarSystem.qml in
// collapse mode; the disk, the lensing and the jets are shaders (shaders/blackhole_*.frag, jet.frag).
// Scene.qml loads one theme at a time and talks to it through `planets`, `sunInfo`, `moonInfo` and bodyPos().
Node {
    id: system
    required property Item scene
    readonly property string title: "Black Hole"
    readonly property real homeZ: 130
    readonly property bool ownCentre: true      // Scene.qml hides its Sun here; the hole takes its place

    readonly property real horizon: 1.15        // radius of the event horizon at the start, in scene units
    readonly property real diskR: 5.2           // outer radius of the accretion disk at the start
    readonly property real diskTilt: 18         // how far the disk is turned toward the camera (degrees)
    readonly property real diskRoll: -9         // and rolled on screen (degrees)
    readonly property real grow: 1 + 0.5 * scene.cycleP     // the hole grows as it feeds
    property real pulse: 0                      // 0..1, a flare of the disk each time a planet goes in
    // the nova takes the hole apart: everything of it fades out while the white-blue star ignites in its place
    readonly property real alive: Math.max(0, 1 - scene.novaBuild * 3)

    // the target -2: what Scene.qml shows for the centre
    readonly property var sunInfo: {
        "name": "Black hole", "size": 2.2, "color": "#ff9a4a",
        "meta": "it feeds on its own planets · an event horizon that keeps growing",
        "desc": "Nothing that crosses the event horizon comes back, not even light. The planets spiral in, one after another, and every one makes the hole brighter and bigger. When the last is gone, it all ends in an explosion, and begins again."
    }
    readonly property var planets: inner.planets
    readonly property var moonInfo: inner.moonInfo

    function bodyPos(i) { return inner.bodyPos(i) }

    // the planets, falling in
    SolarSystem {
        id: inner
        scene: system.scene
        collapse: true
        horizonR: system.horizon * system.grow
        onSwallowed: flare.restart()
    }
    SequentialAnimation {
        id: flare
        NumberAnimation { target: system; property: "pulse"; to: 1; duration: 250; easing.type: Easing.OutQuad }
        NumberAnimation { target: system; property: "pulse"; to: 0; duration: 2200; easing.type: Easing.OutCubic }
    }

    // the camera sits in a node turned by x -38, y 20 (see Scene.qml): anything in `facing` is square on to the camera
    readonly property vector3d facingRot: Qt.vector3d(-38, 20, 0)

    Node {
        id: hole
        scale: Qt.vector3d(system.grow, system.grow, system.grow)
        visible: system.alive > 0.01

        // the event horizon: a black ball. Everything behind it is hidden, the near half of the disk passes in front.
        Model {
            source: "#Sphere"
            scale: Qt.vector3d(system.horizon * 0.02, system.horizon * 0.02, system.horizon * 0.02)
            pickable: false
            materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; diffuseColor: "black" }
        }
        // soft halo while hovered
        Repeater3D {
            model: [ { k: 1.6, o: 0.16, b: -3 }, { k: 2.4, o: 0.06, b: -4 } ]
            Model {
                required property var modelData
                property real gl: system.scene.hovered === -2 ? 1 : 0
                Behavior on gl { NumberAnimation { duration: 160 } }
                visible: gl > 0.01
                source: "#Sphere"
                scale: Qt.vector3d(system.horizon * modelData.k * 0.02, system.horizon * modelData.k * 0.02, system.horizon * modelData.k * 0.02)
                opacity: modelData.o * gl
                depthBias: modelData.b
                pickable: false
                materials: DefaultMaterial { lighting: DefaultMaterial.NoLighting; diffuseColor: "#ff9a4a" }
            }
        }
        // the accretion disk, turned toward the camera a little
        Node {
            eulerRotation: Qt.vector3d(system.diskTilt, 0, system.diskRoll)
            Model {
                source: "#Rectangle"
                eulerRotation.x: -90
                scale: Qt.vector3d(system.diskR / 50, system.diskR / 50, 1)
                pickable: false
                materials: CustomMaterial {
                    sourceBlend: CustomMaterial.One
                    destinationBlend: CustomMaterial.One   // additive: black adds nothing
                    cullMode: Material.NoCulling
                    depthDrawMode: Material.NeverDepthDraw
                    fragmentShader: Qt.resolvedUrl("shaders/blackhole_disk.frag")
                    property real t: system.scene.fxTime
                    property real gain: (0.8 + 0.9 * system.pulse + 0.4 * system.scene.cycleP) * system.alive
                    property real rin: (system.horizon * 1.25) / system.diskR
                    property real phi0: 0.6
                }
            }
        }
        // lensing: the far side of the disk bent over and under the hole, and the photon ring; and the jets
        Node {
            eulerRotation: system.facingRot
            Model {
                source: "#Rectangle"
                scale: Qt.vector3d(4.2 / 50, 4.2 / 50, 1)
                pickable: false
                materials: CustomMaterial {
                    sourceBlend: CustomMaterial.One
                    destinationBlend: CustomMaterial.One
                    cullMode: Material.NoCulling
                    depthDrawMode: Material.NeverDepthDraw
                    fragmentShader: Qt.resolvedUrl("shaders/blackhole_lens.frag")
                    property real t: system.scene.fxTime
                    property real gain: (1.3 + 0.9 * system.pulse) * system.alive
                    property real halfSize: 4.2
                    property real horizon: system.horizon
                    property real roll: system.diskRoll * Math.PI / 180
                    property real dopplerSign: 1
                }
            }
            Node {
                eulerRotation.z: system.diskRoll
                Repeater3D {
                    model: [ 1, -1 ]
                    Model {
                        required property int modelData
                        source: "#Rectangle"
                        y: modelData * (system.horizon * 0.8 + 7)
                        eulerRotation.z: modelData > 0 ? 0 : 180      // the shader runs from the hole outward
                        scale: Qt.vector3d(3 / 50, 7 / 50, 1)
                        pickable: false
                        materials: CustomMaterial {
                            sourceBlend: CustomMaterial.One
                            destinationBlend: CustomMaterial.One
                            cullMode: Material.NoCulling
                            depthDrawMode: Material.NeverDepthDraw
                            fragmentShader: Qt.resolvedUrl("shaders/jet.frag")
                            property real t: system.scene.fxTime + (modelData > 0 ? 0 : 3.1)
                            property real gain: (0.55 + 0.6 * system.pulse + 0.3 * system.scene.cycleP) * system.alive
                        }
                    }
                }
            }
        }
    }
}
