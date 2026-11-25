import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color color: "white"

    implicitWidth: 20
    implicitHeight: 20

    // A flat bob silhouette with Rem's straight fringe and right-side ribbon.
    Shape {
        width: 32
        height: 32
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.width / 32; yScale: root.height / 32 }

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            PathSvg {
                path: "M5 17 C5 10 9 6 16 6 C23 6 27 11 27 18 "
                    + "C27 24 23 28 20 29 L12 29 C7 27 4 22 5 17 Z "
                    + "M10 22 L18 22 C19 19 19.6 15 19 12 "
                    + "C20 15 22 17 24 19 C25 23 22 27 17 29 "
                    + "C14 28 11 26 10 22 Z "
                    + "M21 11 L25 14 L25.6 13.2 L21.6 10.2 Z "
                    + "M21.4 14.2 L25.4 11.2 L24.8 10.4 L20.8 13.4 Z"
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: 1.3
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: "M10 24 Q12 28 17 30 Q22 28 24 23 "
                    + "M20.5 22 Q22 20.5 23.5 22 M16 26.5 Q17 27.2 18 26.5 "
                    + "M7 8 Q6 5 9 5 Q9 2 12 3 Q14 0 16 2 Q19 0 21 3 "
                    + "Q24 2 24 5 Q27 5 26 8 "
                    + "M27 16 Q23 12 26 12 L28 15 Q32 12 31 16 L28 17 "
                    + "Q31 20 29 21 L27.5 17.5 Q25 21 24.5 19 Z"
            }
        }
    }
}
