import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Read-along panel for the Kokoro read-aloud daemon (kokoro-reader/daemon.py).
//
// The daemon streams one JSON snapshot per change over a Unix socket: the
// sentence, each word's [text, start, end] in seconds of its audio, and the
// position. Between snapshots the panel runs its own clock from the moment the
// last one arrived, so it needs a message per sentence, not per word.
//
// The panel shows while the reader has text loaded and its "panel" setting is
// on (read-aloud panel). It is click-through and never takes keyboard focus.
// All text from the daemon is the user's selection: rendered as plain text.
Item {
  id: root

  property var omarchyPath
  property var shell
  property var manifest

  readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/kokoro-reader-events.sock"

  property var snap: null
  property real receivedAt: 0      // Date.now() when snap arrived
  property real clock: 0           // ms, ticks while playing

  readonly property bool playing: !!snap && snap.state === "playing"
  readonly property bool shown: events.connected && !!snap && snap.panel === true && snap.state !== "stopped"
  readonly property var words: snap && Array.isArray(snap.words) ? snap.words : []
  readonly property real elapsed: {
    if (!snap) return 0
    var since = playing ? Math.max(0, clock - receivedAt) / 1000 : 0
    return snap.phase === "repeat" ? since : Number(snap.pos || 0) + since
  }
  readonly property int currentWord: {
    if (!snap || snap.phase !== "speaking" || words.length === 0) return -1
    var t = elapsed
    var last = words[words.length - 1]
    if (t > Number(last[2]) + 0.05) return words.length   // all spoken: trailing pause
    var current = 0
    for (var i = 0; i < words.length; i++) {
      if (Number(words[i][1]) <= t) current = i
      else break
    }
    return current
  }
  readonly property real repeatLeft: snap && snap.phase === "repeat"
    ? Math.max(0, Number(snap.repeatLeft || 0) - elapsed) : 0

  function handle(line) {
    try {
      var next = JSON.parse(line)
      if (!next || typeof next !== "object") return
      if (!Array.isArray(next.words)) next.words = []
      if (next.words.length > 400) next.words = next.words.slice(0, 400)
      snap = next
      receivedAt = Date.now()
      clock = receivedAt
    } catch (e) {}
  }

  function voiceName(id) {
    var s = String(id || "")
    var name = s.indexOf("_") >= 0 ? s.slice(s.indexOf("_") + 1) : s
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Socket {
    id: events
    path: root.socketPath
    connected: false
    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handle(line) }
    }
    onConnectedChanged: if (!connected) root.snap = null
    onError: function(error) {
      // Quickshell 0.3.2 still uses the socket after emitting error;
      // disconnecting inside the handler can clear it under its feet.
      Qt.callLater(function() { events.connected = false })
    }
  }

  // The daemon starts on the first read and exits when idle: keep trying.
  Timer {
    interval: 1000
    repeat: true
    running: !events.connected
    onTriggered: events.connected = true
  }

  Timer {
    interval: 33
    repeat: true
    running: root.shown && root.playing
    onTriggered: root.clock = Date.now()
  }

  OverlayWindow {
    shown: root.shown
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-read-along"
    mask: Region {}

    BorderSurface {
      id: card
      readonly property int pad: Style.space(18)
      width: Math.min(parent.width - Style.space(80), Style.space(860))
      height: card.borderTop + card.pad + content.implicitHeight + card.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      // Above the OSD (bottom margin 67 + its own height), so volume and speed
      // pop-ups never cover the sentence.
      anchors.bottomMargin: Style.space(150)
      color: Util.alpha(Commons.Color.background, 0.94)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Column {
        id: content
        x: card.borderLeft + card.pad
        y: card.borderTop + card.pad
        width: card.width - card.borderLeft - card.borderRight - 2 * card.pad
        spacing: Style.space(10)

        // Header: position, speed, voice, mode, phase.
        Row {
          spacing: Style.space(14)
          Repeater {
            model: {
              if (!root.snap) return []
              var parts = [
                strings.t("header.position").arg(Number(root.snap.index) + 1).arg(Number(root.snap.count)),
                strings.t("header.speed").arg(Commons.I18n.formatNumber(Number(root.snap.speed), 1)),
                root.voiceName(root.snap.voice)
              ]
              if (root.snap.shadow) parts.push(strings.t("header.shadowing"))
              if (root.snap.state === "paused") parts.push(strings.t("phase.paused"))
              else if (root.snap.phase === "loading") parts.push(strings.t("phase.loading"))
              return parts
            }
            Text {
              required property string modelData
              textFormat: Text.PlainText
              text: modelData
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Util.alpha(Commons.Color.popups.text, 0.6)
            }
          }
        }

        // The sentence, word by word: spoken words full colour, the current one
        // on an accent pill, the rest dimmed. A pill (not bold) keeps the line
        // breaks from shifting as the highlight moves.
        Flow {
          width: parent.width
          spacing: Style.space(7)
          Repeater {
            model: root.words
            Item {
              required property var modelData
              required property int index
              readonly property bool current: index === root.currentWord
              readonly property bool spoken: root.snap && (root.snap.phase === "repeat" || index < root.currentWord)
              width: word.implicitWidth
              height: word.implicitHeight
              Rectangle {
                anchors.fill: parent
                anchors.margins: -Style.space(3)
                radius: Math.max(2, Style.cornerRadius / 2)
                color: Commons.Color.accent
                opacity: parent.current ? 1 : 0
              }
              Text {
                id: word
                textFormat: Text.PlainText
                text: String(modelData[0])
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                color: parent.current ? Commons.Color.background
                  : Util.alpha(Commons.Color.popups.text, parent.spoken ? 1 : 0.55)
              }
            }
          }
        }

        // Shadowing: the gap left to repeat the sentence.
        Column {
          visible: !!root.snap && root.snap.phase === "repeat"
          width: parent.width
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: strings.t("phase.repeat")
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            color: Commons.Color.accent
          }
          Rectangle {
            width: parent.width
            height: Math.max(Style.space(4), 2)
            color: Util.alpha(Commons.Color.popups.text, 0.2)
            Rectangle {
              anchors.left: parent.left
              height: parent.height
              width: parent.width * (root.snap && Number(root.snap.repeat) > 0
                ? Math.min(1, root.repeatLeft / Number(root.snap.repeat)) : 0)
              color: Commons.Color.accent
            }
          }
        }

        Text {
          visible: !!root.snap && String(root.snap.next || "") !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.snap ? String(root.snap.next || "").slice(0, 600) : ""
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          color: Util.alpha(Commons.Color.popups.text, 0.4)
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }
    }
  }
}
