import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// The sidebar switcher (SUPER + TAB with two or more sidebars): live previews of
// every sidebar in the middle of the focused screen over a dimmed backdrop,
// styled like Omarchy's theme and background picker ("cards") or as a cover
// flow ("coverflow"; SUPER + T swaps them while it's open). hypr/sidebar.lua owns
// the keys and the choice; it sends the whole state with each change. It takes
// no keyboard focus and no clicks, so SUPER's release still reaches Hyprland.
Scope {
  id: root

  property bool open: false
  property string session: ""
  property int seq: -1
  property int index: 0
  property var items: []
  property string monitor: ""
  property string style: "cards"

  // Messages come from separate processes and can arrive out of order: only a
  // newer one counts. Each load of sidebar.lua numbers them afresh under a new
  // session id ("<load time>-<random>"), so a later session's messages always
  // count, and a straggler from an earlier one never does.
  function sessionTime(id) {
    return Number(String(id).split("-")[0]) || 0
  }

  function newer(messageSession, messageSeq) {
    if (messageSession !== session) {
      if (sessionTime(messageSession) < sessionTime(session)) return false
      session = messageSession
      seq = messageSeq
      return true
    }
    if (messageSeq <= seq) return false
    seq = messageSeq
    return true
  }

  function show(payload) {
    var p = JSON.parse(payload)
    if (!newer(String(p.session), p.seq)) return
    // The shell's list of Hyprland windows follows its event connection, which
    // is never remade once Hyprland closes it (quickshell #989): fetched afresh
    // on opening, so new sidebars still have previews.
    if (!open) Hyprland.refreshToplevels()
    monitor = p.monitor || ""
    style = p.style === "coverflow" ? "coverflow" : "cards"
    items = p.items
    index = p.index
    open = true
  }

  // "<session> <seq>"
  function close(message) {
    var parts = String(message).split(" ")
    if (!newer(parts[0], Number(parts[1]))) return
    open = false
  }

  // The window to capture, by its Hyprland address (with or without "0x").
  function capture(address) {
    var wanted = String(address).replace(/^0x/, "")
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      if (String(all[i].address).replace(/^0x/, "") === wanted) return all[i].wayland
    }
    return null
  }

  IpcHandler {
    target: "sidebar-switcher"
    function show(payload: string): string { root.show(payload); return "ok" }
    function close(message: string): string { root.close(message); return "ok" }
    function state(): string { return (root.open ? "open" : "closed") + " " + root.session + " " + root.seq }
  }

  PanelWindow {
    id: panel

    // The focused monitor, as sidebar.lua sends it (not Hyprland.focusedMonitor,
    // which goes stale with the shell's event connection).
    screen: {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === root.monitor) return screens[i]
      }
      return screens.length > 0 ? screens[0] : null
    }
    visible: root.open || content.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-sidebar-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    // Laid out like Omarchy's theme and background picker: the highlighted
    // sidebar as a large slanted card, the others as narrow slanted slices
    // overlapping on either side, in the picker's colours.
    Item {
      id: content
      anchors.fill: parent
      opacity: root.open ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        color: Color.imagePicker.scrim
      }

      // Cover flow darkens the screen further, so the covers stand out.
      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.style === "coverflow" ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      readonly property int expandedHeight: 475
      readonly property int sliceWidth: 108
      readonly property int sliceHeight: 432
      readonly property int sliceSpacing: -30
      readonly property int skewOffset: 28
      readonly property real step: sliceWidth + sliceSpacing

      // The highlighted card is a little wider than its window's shape at the
      // picker's height; the preview fills it, cropped top and bottom.
      readonly property real widen: 1.4
      function cardWidth(it) {
        var w = expandedHeight * widen * (it.width / Math.max(1, it.height))
        return Math.max(260, Math.min(768, w))
      }

      // The window's preview at the card's width, at least the card's height.
      function previewHeight(it) {
        return Math.max(expandedHeight, cardWidth(it) * (it.height / Math.max(1, it.width)))
      }

      readonly property var chosenItem: root.items[root.index] || null
      readonly property real chosenWidth: chosenItem ? cardWidth(chosenItem) : 0

      // Each look fades in and out on its own; its previews are dropped once it
      // (or the whole switcher) has faded out, so nothing hidden is captured.
      function shows(look, view) {
        return (root.open || content.opacity > 0) && (root.style === look || view.opacity > 0)
      }

      Item {
        id: carousel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        width: content.chosenWidth
        height: content.expandedHeight
        opacity: root.style === "cards" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Repeater {
          model: content.shows("cards", carousel) ? root.items : []

          delegate: Item {
            id: card
            required property var modelData
            required property int index

            readonly property int relative: index - root.index
            readonly property bool chosen: relative === 0
            // The window at the highlighted card's width; a slice shows its middle.
            readonly property real fullWidth: content.cardWidth(modelData)

            x: chosen ? 0 : (relative < 0
              ? relative * content.step
              : content.chosenWidth + content.sliceSpacing + (relative - 1) * content.step)
            y: chosen ? 0 : (content.expandedHeight - content.sliceHeight) / 2
            z: chosen ? 100 : 50 - Math.min(Math.abs(relative), 40)
            width: chosen ? fullWidth : content.sliceWidth
            height: chosen ? content.expandedHeight : content.sliceHeight

            readonly property real topLeft: content.skewOffset
            readonly property real topRight: width
            readonly property real bottomRight: width - content.skewOffset
            readonly property real bottomLeft: 0

            Item {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "white"
                  strokeColor: "transparent"
                  startX: card.topLeft; startY: 0
                  PathLine { x: card.topRight; y: 0 }
                  PathLine { x: card.bottomRight; y: card.height }
                  PathLine { x: card.bottomLeft; y: card.height }
                  PathLine { x: card.topLeft; y: 0 }
                }
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }

              Rectangle {
                anchors.fill: parent
                color: Color.background
              }

              ScreencopyView {
                anchors.centerIn: parent
                width: card.fullWidth
                height: content.previewHeight(card.modelData)
                captureSource: root.capture(card.modelData.address)
                live: true
              }

              Rectangle {
                anchors.fill: parent
                color: Util.alpha(Color.background, card.chosen ? 0 : 0.42)
              }
            }

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "transparent"
                strokeColor: card.chosen ? Color.imagePicker.selectedBorder : Color.imagePicker.unselectedBorder
                strokeWidth: card.chosen ? 3 : 1
                startX: card.topLeft; startY: 0
                PathLine { x: card.topRight; y: 0 }
                PathLine { x: card.bottomRight; y: card.height }
                PathLine { x: card.bottomLeft; y: card.height }
                PathLine { x: card.topLeft; y: 0 }
              }
            }
          }
        }
      }

      // Cover flow: the highlighted sidebar faces you in the middle, the others
      // turned away on either side, overlapping, each over a faint reflection.
      // Moving along glides them round.
      readonly property int flowHeight: 440
      readonly property int flowGap: 70 // from the middle card's edge to the first one beside it
      readonly property int flowStep: 96 // between the ones further out
      readonly property real flowAngle: 58
      readonly property real flowReflection: 0.3 // of a card's height
      readonly property int flowRadius: 18
      function flowWidth(it) {
        return Math.max(240, Math.min(640, flowHeight * (it.width / Math.max(1, it.height))))
      }
      readonly property real flowChosenWidth: chosenItem ? flowWidth(chosenItem) : 0

      Item {
        id: flow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -10
        width: content.flowChosenWidth
        height: content.flowHeight
        opacity: root.style === "coverflow" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Repeater {
          model: content.shows("coverflow", flow) ? root.items : []

          delegate: Item {
            id: tile
            required property var modelData
            required property int index

            readonly property int relative: index - root.index
            readonly property bool chosen: relative === 0
            readonly property int side: relative < 0 ? -1 : (relative > 0 ? 1 : 0)
            readonly property real aspect: modelData.width / Math.max(1, modelData.height)

            width: content.flowWidth(modelData)
            height: content.flowHeight
            // Centred on its spot: the middle, or out to the side.
            x: flow.width / 2 - width / 2 + (side === 0 ? 0
              : side * (content.flowChosenWidth / 2 + content.flowGap + (Math.abs(relative) - 1) * content.flowStep))
            z: 100 - Math.abs(relative)
            scale: chosen ? 1 : 0.88
            property real angle: -side * content.flowAngle

            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            Behavior on angle { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            // Drawn into a multisampled layer, turned inside it, so the turned
            // card's edges and corners come out smooth. The layer reaches past
            // the card, as perspective makes its near edge taller, and covers
            // the reflection below.
            readonly property int pad: 48
            Item {
              x: -tile.pad
              y: -tile.pad
              width: tile.width + 2 * tile.pad
              height: tile.height * (1 + content.flowReflection) + 6 + 2 * tile.pad
              layer.enabled: true
              layer.smooth: true
              layer.samples: 4

              Item {
                x: tile.pad
                y: tile.pad
                width: tile.width
                height: tile.height
                transform: Rotation {
                  origin.x: tile.width / 2
                  origin.y: tile.height / 2
                  axis { x: 0; y: 1; z: 0 }
                  angle: tile.angle
                }

                Rectangle {
                  id: corners
                  width: tile.width
                  height: tile.height
                  radius: content.flowRadius
                  antialiasing: true
                  visible: false
                  layer.enabled: true
                  layer.smooth: true
                }

                // The card as drawn, rounded corners and all, for the reflection to
                // copy (copying `face` itself would skip its own corner mask).
                Item {
                  id: cover
                  width: tile.width
                  height: tile.height

                  Item {
                    id: face
                    width: tile.width
                    height: tile.height
                    clip: true
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: OpacityMask {
                      maskSource: corners
                    }

                    Rectangle {
                      anchors.fill: parent
                      color: Color.background
                    }

                    // The window filling the card, cropped to it.
                    ScreencopyView {
                      anchors.centerIn: parent
                      width: Math.max(tile.width, tile.height * tile.aspect)
                      height: width / tile.aspect
                      captureSource: root.capture(tile.modelData.address)
                      live: true
                    }

                    Rectangle {
                      anchors.fill: parent
                      color: Util.alpha(Color.background, tile.chosen ? 0 : 0.42)
                      Behavior on color { ColorAnimation { duration: 280 } }
                    }

                  }
                }

                // The bottom of the card, upside down beneath it, fading out. The
                // whole of it is flipped, as the mask copies its source unflipped:
                // so the end nearest the card is the bottom of `fade`.
                Item {
                  id: reflection
                  y: face.height + 6
                  width: face.width
                  height: Math.round(face.height * content.flowReflection)
                  opacity: 0.3
                  transform: Scale { origin.y: reflection.height / 2; yScale: -1 }

                  ShaderEffectSource {
                    id: mirror
                    anchors.fill: parent
                    sourceItem: cover
                    sourceRect: Qt.rect(0, face.height - reflection.height, face.width, reflection.height)
                    visible: false
                  }

                  Rectangle {
                    id: fade
                    anchors.fill: parent
                    visible: false
                    gradient: Gradient {
                      GradientStop { position: 0.0; color: "transparent" }
                      GradientStop { position: 1.0; color: "white" }
                    }
                  }

                  OpacityMask {
                    anchors.fill: parent
                    source: mirror
                    maskSource: fade
                  }
                }
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        // Above the covers in cover flow (their reflections are below), else below.
        y: root.style === "coverflow"
          ? flow.y - height - Style.space(24)
          : carousel.y + carousel.height + Style.space(16)
        anchors.horizontalCenter: carousel.horizontalCenter
        width: Math.max(root.style === "coverflow" ? content.flowChosenWidth : content.chosenWidth, 480)
        text: content.chosenItem ? content.chosenItem.title : ""
        color: Color.imagePicker.text
        style: Text.Outline
        styleColor: Util.alpha(Color.background, 0.7)
        font.pixelSize: Style.font.display
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
