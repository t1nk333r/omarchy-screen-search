import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Presentation for every OSD state. Reads everything off `osd` (SearchOsd).
Item {
  id: root
  required property var osd

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(Color.popups.text, 0.62)
  readonly property string family: Style.font.family
  readonly property int maxWidth: Style.space(460)
  readonly property int previewSize: Number(osd.setting("previewSize", 160))
  readonly property var summary: Model.summarize(osd.payload.text || "", 6, 420)
  readonly property bool showFull: osd.expanded || !summary.truncated

  implicitWidth: column.implicitWidth
  implicitHeight: column.implicitHeight

  Column {
    id: column
    spacing: Style.spacing.lg

    // --- header -------------------------------------------------------------
    Row {
      spacing: Style.spacing.md
      Text {
        text: osd.mode === "ocr" || osd.payload.kind === "text" ? "󰴑" : "󰍉"
        color: root.fg; font.family: root.family; font.pixelSize: Style.font.iconLarge
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: osd.state === "result"
          ? (osd.payload.kind === "text" ? "OCR result" : "Search with " + osd.providerName)
          : (osd.mode === "ocr" ? "OCR" : "Circle to Search")
        color: root.fg; font.family: root.family; font.pixelSize: Style.font.title; font.bold: true
      }
    }

    // --- selecting / processing / failed -----------------------------------
    Text {
      visible: osd.state === "selecting" || osd.state === "processing" || osd.state === "failed"
      text: osd.state === "failed" ? osd.message : osd.busyLabel
      color: osd.state === "failed" ? Color.urgent : root.dim
      font.family: root.family; font.pixelSize: Style.font.body
    }

    // --- image result -------------------------------------------------------
    Row {
      visible: osd.state === "result" && osd.payload.kind === "image" && !osd.confirmingUpload
      spacing: Style.spacing.lg
      BorderSurface {
        width: root.previewSize; height: root.previewSize
        radius: Style.spacing.labelGap
        color: Util.alpha(root.fg, 0.05)
        borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
        Image {
          anchors.fill: parent; anchors.margins: Style.space(2)
          fillMode: Image.PreserveAspectFit
          asynchronous: true; cache: false
          source: osd.payload.kind === "image" && osd.payload.file ? "file://" + osd.payload.file : ""
        }
      }
      Column {
        spacing: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: osd.caps.visual ? "Enter · search with " + osd.providerName : osd.providerName + " has no visual search"
          color: osd.caps.visual ? root.fg : Color.urgent
          font.family: root.family; font.pixelSize: Style.font.body
        }
        Text {
          text: osd.caps.visual ? "The image is copied for you to paste on the provider page.\nNothing is uploaded by Screen Search." : "Use OCR to search the text instead."
          color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall
        }
        Text { text: "W · search with…"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
      }
    }

    // --- text result --------------------------------------------------------
    Flickable {
      visible: osd.state === "result" && osd.payload.kind === "text" && !osd.confirmingUpload
      width: Math.min(root.maxWidth, textItem.implicitWidth)
      height: Math.min(Style.space(260), textItem.implicitHeight)
      contentHeight: textItem.implicitHeight
      clip: true
      interactive: contentHeight > height
      Text {
        id: textItem
        width: root.maxWidth
        text: root.showFull ? (osd.payload.text || "") : root.summary.text
        color: root.fg; font.family: root.family; font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
      }
    }
    Text {
      visible: osd.state === "result" && osd.payload.kind === "text" && root.summary.truncated && !osd.confirmingUpload
      text: osd.expanded ? "E · collapse" : "E · expand"
      color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption
    }

    // --- transient message --------------------------------------------------
    Text {
      visible: osd.state === "result" && osd.message !== ""
      text: osd.message
      color: Color.accent; font.family: root.family; font.pixelSize: Style.font.bodySmall
    }

    // --- provider picker ("Search with…") ----------------------------------
    Column {
      visible: osd.state === "result" && osd.pickingProvider && !osd.confirmingUpload
      spacing: Style.spacing.xs
      Repeater {
        model: osd.providers
        delegate: Button {
          required property var modelData
          required property int index
          text: modelData.name + (modelData.visual ? "" : "  (text only)")
          leftAlign: true
          width: Style.space(220)
          hasCursor: index === osd.pickerCursor
          selected: modelData.current
          foreground: root.fg
          onClicked: osd.chooseProvider(index)
        }
      }
    }

    // --- upload consent (public-url mode; shown before EVERY upload) --------
    Column {
      visible: osd.confirmingUpload
      spacing: Style.spacing.md
      width: Math.min(root.maxWidth, Style.space(420))
      Text {
        text: "Upload to " + (osd.consentInfo ? osd.consentInfo.host : "") + "?"
        color: root.fg; font.family: root.family; font.pixelSize: Style.font.title; font.bold: true
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: osd.consentInfo
          ? "This will upload the screenshot to " + osd.consentInfo.host + ", a free public file host.\n" +
            "• Anyone with the link can view it until it expires (" + osd.consentInfo.expiryHours + " h). " +
            (osd.consentInfo.deletable ? "It is deleted right after the search." : "It cannot be deleted early.") + "\n" +
            "• The host may log your IP address. " + osd.consentInfo.provider + " will download it from there.\n" +
            "Nothing has been uploaded yet."
          : ""
        color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall
      }
      Row {
        spacing: Style.spacing.controlGap
        Button {
          text: "Upload & search"
          bordered: true; selected: true
          foreground: root.fg
          onClicked: { osd.confirmingUpload = false; osd.runAction("visual-confirmed") }
        }
        Button {
          text: "Cancel"
          bordered: true
          foreground: root.fg
          onClicked: { osd.confirmingUpload = false; osd.consentInfo = null }
        }
      }
      Text { text: "Enter · upload    Esc · back"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption }
    }

    // --- actions ------------------------------------------------------------
    Row {
      visible: osd.state === "result" && !osd.pickingProvider && !osd.confirmingUpload
      spacing: Style.spacing.controlGap
      Repeater {
        model: osd.actions
        delegate: Button {
          required property var modelData
          required property int index
          text: modelData.label
          bordered: true
          hasCursor: index === osd.cursor
          selected: modelData.def === true
          foreground: root.fg
          tooltipText: modelData.key ? modelData.key.toUpperCase() : ""
          onClicked: { osd.cursor = index; osd.runAction(modelData.id) }
          onHovered: function(h) { if (h) osd.cursor = index }
        }
      }
    }

    Text {
      visible: osd.state === "result" && !osd.pickingProvider && !osd.confirmingUpload
      text: "Enter · " + (osd.actions[osd.cursor] ? osd.actions[osd.cursor].label : "") + "    Esc · close"
      color: root.dim; font.family: root.family; font.pixelSize: Style.font.caption
    }
  }
}
