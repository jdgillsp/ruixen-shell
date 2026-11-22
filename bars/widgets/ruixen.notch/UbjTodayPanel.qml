import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Read-only UBJ Today & Attention panel for Ruixen Notch.
// Polls only while active && visible (respecting idle-polling-gating).
Item {
  id: root

  property bool active: false
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#8aadf4"
  property color successColor: "#3ecf5b"
  property color warningColor: "#e8c34a"
  property color dangerColor: "#e05252"
  property color cardSurface: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.04)
  property color cardBorderColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)
  property string fontFamily: "JetBrainsMono Nerd Font"

  property bool online: false
  property string errorText: ""
  property string checkedAt: ""
  property var summary: ({})
  property var attention: []
  property var compute: ({})
  property var backlog: ({})
  property bool requestTimedOut: false

  function refresh() {
    if (!active || !visible || reader.running)
      return;
    requestTimedOut = false;
    reader.command = [
      "python3",
      decodeURIComponent(Qt.resolvedUrl("ubj-today.py").toString().replace(/^file:\/\//, ""))
    ];
    reader.running = true;
  }

  function timeoutReader() {
    if (!reader.running)
      return;
    requestTimedOut = true;
    online = false;
    errorText = "UBJ status read timed out";
    reader.signal(9);
  }

  onActiveChanged: if (active && visible) Qt.callLater(refresh)
  onVisibleChanged: if (active && visible) Qt.callLater(refresh)

  Timer {
    interval: 15000
    repeat: true
    running: root.active && root.visible
    onTriggered: root.refresh()
  }

  Timer {
    interval: 6000
    running: reader.running
    onTriggered: root.timeoutReader()
  }

  Process {
    id: reader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.active || root.requestTimedOut)
          return;
        try {
          var data = JSON.parse(text);
          root.online = !!data.online;
          root.errorText = data.error || "";
          root.summary = data.summary || ({});
          root.attention = data.attention || [];
          root.compute = data.compute || ({});
          root.backlog = data.backlog || ({});
          root.checkedAt = Qt.formatTime(new Date(), "hh:mm:ss");
        } catch (e) {
          root.online = false;
          root.errorText = "Unable to parse UBJ snapshot";
        }
      }
    }
    onExited: (code, status) => {
      if (code !== 0 && !root.requestTimedOut && root.active) {
        root.online = false;
        root.errorText = "UBJ helper exited with error";
      }
    }
  }

  component StatPill: Rectangle {
    property string label: ""
    property string value: "0"
    property color tone: root.textColor
    radius: 8
    color: root.cardSurface
    border.width: 1
    border.color: root.cardBorderColor
    Layout.fillWidth: true
    implicitHeight: 46

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 6
      spacing: 1
      Text {
        text: value
        color: tone
        font.family: root.fontFamily
        font.pixelSize: 14
        font.bold: true
      }
      Text {
        text: label
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 9
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.rightMargin: 10
    anchors.bottomMargin: 10
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: root.online ? "UBJ Today" : "UBJ Offline"
        color: root.online ? root.textColor : root.warningColor
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
      }

      Text {
        text: root.checkedAt ? ("updated " + root.checkedAt) : ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
        Layout.fillWidth: true
        elide: Text.ElideRight
      }

      Rectangle {
        radius: 6
        color: root.cardSurface
        border.width: 1
        border.color: root.cardBorderColor
        implicitWidth: refreshLbl.implicitWidth + 14
        implicitHeight: 22
        Text {
          id: refreshLbl
          anchors.centerIn: parent
          text: reader.running ? "…" : "Refresh"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: 10
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.refresh()
        }
      }
    }

    Rectangle {
      visible: !root.online
      Layout.fillWidth: true
      radius: 10
      color: root.cardSurface
      border.width: 1
      border.color: root.cardBorderColor
      implicitHeight: offlineTxt.implicitHeight + 20

      Text {
        id: offlineTxt
        anchors.fill: parent
        anchors.margins: 10
        wrapMode: Text.Wrap
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 11
        text: root.errorText || "Waiting for local UseBestJudgment API on 127.0.0.1:7742…"
      }
    }

    RowLayout {
      visible: root.online
      Layout.fillWidth: true
      spacing: 6

      StatPill {
        label: "waiting"
        value: String(root.summary.waiting_on_user || 0)
        tone: (root.summary.waiting_on_user || 0) > 0 ? root.warningColor : root.textColor
      }
      StatPill {
        label: "working"
        value: String(root.summary.working || 0)
        tone: (root.summary.working || 0) > 0 ? root.successColor : root.textColor
      }
      StatPill {
        label: "failing"
        value: String(root.summary.failing_checks || 0)
        tone: (root.summary.failing_checks || 0) > 0 ? root.dangerColor : root.textColor
      }
      StatPill {
        label: "unpushed"
        value: String(root.summary.unpushed_projects || 0)
        tone: (root.summary.unpushed_projects || 0) > 0 ? root.warningColor : root.textColor
      }
    }

    RowLayout {
      visible: root.online
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 8

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: root.cardSurface
        border.width: 1
        border.color: root.cardBorderColor

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 6

          Text {
            text: "ATTENTION"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          Text {
            visible: root.attention.length === 0
            text: "All clear — no waiting sessions, failing checks, or unpushed commits."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 11
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          Repeater {
            model: root.attention
            delegate: RowLayout {
              Layout.fillWidth: true
              spacing: 6
              Rectangle {
                width: 6
                height: 6
                radius: 3
                color: modelData.kind === "failing" ? root.dangerColor : root.warningColor
              }
              Text {
                text: modelData.project + " — " + modelData.detail
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }

          Item { Layout.fillHeight: true }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: root.cardSurface
        border.width: 1
        border.color: root.cardBorderColor

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 6

          Text {
            text: "COMPUTE PLAN"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          Text {
            text: "Budget: " + (root.compute.budget_remaining || 0) + "/" + (root.compute.budget_total || 0)
                  + " · " + (root.compute.mode || "quota_weighted")
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Text {
            text: "Eligible: " + ((root.compute.eligible_agents && root.compute.eligible_agents.length > 0)
                  ? root.compute.eligible_agents.join(", ") : "none")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Repeater {
            model: root.compute.slots || []
            delegate: Text {
              text: "#" + modelData.slot + " " + modelData.project + " (" + modelData.agent + "): " + modelData.title
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 10
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          Text {
            visible: root.backlog && root.backlog.ready !== undefined
            text: "Board: " + (root.backlog.ready || 0) + " ready · "
                  + (root.backlog.blocked || 0) + " blocked · "
                  + (root.backlog.held || 0) + " held · "
                  + (root.backlog.done || 0) + " done"
                  + ((root.backlog.flagged || 0) > 0 ? (" · " + root.backlog.flagged + " flagged") : "")
            color: (root.backlog.flagged || 0) > 0 ? root.dangerColor : root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Item { Layout.fillHeight: true }
        }
      }
    }
  }
}
