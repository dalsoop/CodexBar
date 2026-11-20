import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The opencodex hub account list of one provider's detail. The backend words every line; a Switch click
// only asks the popup to show the confirmation, which alone can start a switch.
ColumnLayout {
    id: root
    property var view: null
    property color primaryText: "black"
    property color secondaryText: "gray"
    property color dividerColor: "lightgray"
    property color hoverColor: "transparent"
    signal switchRequested(int index)
    readonly property var lines: view ? [view.note, view.message, view.error].concat(view.header || [], view.notices || [])
        .filter(function(line) { return line !== "" && line !== undefined; }) : []
    readonly property var accounts: view && view.hasPool ? view.accounts : []
    visible: lines.length > 0 || accounts.length > 0
    spacing: 6

    Rectangle { Layout.fillWidth: true; height: 1; color: root.dividerColor }
    Label {
        visible: root.accounts.length > 0
        text: "opencodex hub accounts"
        color: root.primaryText
        font.pixelSize: 15; font.weight: Font.DemiBold
    }
    Repeater {
        model: root.lines
        Label {
            required property var modelData
            text: modelData
            color: root.secondaryText; font.pixelSize: 12
            Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        }
    }
    Repeater {
        model: root.accounts
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: row.implicitHeight + 14
            radius: 8
            color: modelData.active ? root.hoverColor : "transparent"
            RowLayout {
                id: row
                anchors.fill: parent; anchors.margins: 7
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: modelData.title
                        color: root.primaryText; font.pixelSize: 13
                        Layout.fillWidth: true; elide: Text.ElideMiddle; textFormat: Text.PlainText
                    }
                    Label {
                        text: modelData.quota
                        visible: text !== ""
                        color: root.secondaryText; font.pixelSize: 11
                        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    }
                }
                Label {
                    visible: modelData.active
                    text: "Active"
                    color: root.primaryText; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Button {
                    visible: !modelData.active
                    text: "Switch"
                    enabled: modelData.canSwitch
                    Accessible.name: "Switch the opencodex hub to " + modelData.title
                    onClicked: root.switchRequested(modelData.index)
                }
            }
        }
    }
}
