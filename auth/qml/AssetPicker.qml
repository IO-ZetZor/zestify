import QtQuick
import QtQuick.Dialogs
import Zestify.Login 1.0

FileDialog {
    id: root
    property string fieldKey: ""
    title: fieldKey.startsWith("fonts.") ? "Choose a font file" : "Choose a background or icon"
    fileMode: FileDialog.OpenFile
    nameFilters: fieldKey.startsWith("fonts.") ? ["Font files (*.ttf *.otf *.ttc)", "All files (*)"]
        : fieldKey === "background.source" ? ["Wallpapers (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.svg *.gif *.apng *.mp4 *.webm *.mkv *.mov *.m4v *.avi *.ogv)", "All files (*)"]
        : ["Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.svg *.gif)", "All files (*)"]
    onAccepted: Theme.selectAsset(fieldKey, selectedFile)
}
