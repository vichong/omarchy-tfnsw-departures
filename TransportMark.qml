import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Transport for NSW mark (the "waratah" arc), rendered natively so it
// scales crisply into a bar slot. Monochrome by default from the official
// one-colour artwork, which carries its own knock-out gaps; `colorful` draws
// the gradient artwork used on transportnsw.info instead.
//
// Source: TfNSW Open Data "Transport Mode Symbols and Pictograms" (Warahop
// logo, CC BY-NC) and the transportnsw.info header SVG. Used to identify the
// service the plugin connects to; not an endorsement.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool colorful: false
  property real dim: 1.0

  // Both artworks share the mark's 4:3 aspect; width follows the height.
  readonly property real aspect: 1.3293
  width: iconSize * aspect
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  // --- monochrome: the four pieces of the mark in one colour at graded
  // opacities (arc, swoosh, leg, dot), so it reads as tones rather than a
  // silhouette in the bar — the same treatment as the sibling Gorelo mark.
  readonly property real monoScale: iconSize / 33.4
  Shape {
    visible: !root.colorful
    width: 44.4
    height: 33.4
    x: -67.8 * root.monoScale
    y: -4.9 * root.monoScale
    transform: Scale { xScale: root.monoScale; yScale: root.monoScale }
    preferredRendererType: Shape.CurveRenderer
    opacity: root.dim

    ShapePath {
      strokeWidth: -1
      fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.72)
      PathSvg { path: "M67.9316 34.7935C67.8782 34.8454 67.8462 34.9174 67.8462 34.996V34.9987C67.8462 35.1546 67.973 35.2825 68.1304 35.2825C68.1825 35.2825 68.2305 35.2692 68.2719 35.2452L68.2959 35.2239C72.2243 31.6939 78.6706 26.7728 87.1078 27.1952C90.3824 27.3578 93.3514 28.3905 96.0575 29.9363C98.845 31.5287 104.08 36.8096 104.08 36.8096C104.927 37.6745 106.116 38.2182 107.412 38.2262C107.412 38.2262 108.162 38.2115 108.805 38.005C108.993 37.945 109.076 37.9103 109.076 37.9103C109.441 37.7571 111.592 36.711 111.275 33.9993C111.145 32.8972 110.598 31.7805 109.564 30.7851C109.337 30.5666 101.831 22.0955 87.5322 23.424C78.1489 24.7033 71.6145 30.4773 67.9316 34.7935Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.5)
      PathSvg { path: "M68.408 35.056C68.3813 35.1852 68.2665 35.2825 68.1304 35.2825C67.9743 35.2825 67.8462 35.1559 67.8462 34.9987C67.8462 34.9987 67.8462 34.9747 67.8489 34.9627C68.0063 32.8039 71.7466 12.497 75.7817 37.8144C75.7817 37.8144 75.787 37.8637 75.7897 37.8983C75.7937 37.9636 75.775 38.0249 75.775 38.0249C75.7337 38.1862 75.5735 38.2315 75.4428 38.2008C75.3347 38.1755 75.2466 38.0982 75.2226 37.9823C75.2226 37.9823 73.2517 28.2785 71.0874 28.3865C70.1587 28.4518 69.4848 30.1441 68.4173 35.0147C68.4146 35.028 68.4093 35.056 68.4093 35.056H68.408Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 1.0)
      PathSvg { path: "M111.923 31.9631C111.654 30.8131 105.849 4.90008 92.0303 8.30878C88.8812 9.08433 86.4473 11.8054 84.4644 14.4412C79.1269 21.5451 75.9778 34.9214 75.2319 37.8544C75.1839 38.0396 75.2973 38.1689 75.4427 38.2022C75.5735 38.2329 75.7323 38.1876 75.775 38.0263C76.1833 36.4552 77.3162 32.6334 77.8606 31.125C79.6326 26.0332 84.9248 16.6959 90.6692 16.7519C98.2498 16.8239 101.886 30.8465 102.917 34.7549C103.414 36.7284 105.266 38.2155 107.414 38.2275C109.994 38.2369 112.098 36.1607 112.11 33.5809C112.11 33.365 112.089 32.6614 111.924 31.9631H111.923Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.85)
      PathSvg { path: "M110.864 33.5396C110.855 35.4598 109.29 37.0069 107.367 36.9989C105.444 36.9883 103.895 35.4252 103.904 33.5076C103.914 31.5874 105.479 30.0376 107.4 30.0483C109.325 30.0563 110.874 31.6207 110.863 33.5396H110.864Z" }
    }
  }

  // --- colour (gradient artwork, px units)
  readonly property real colourScale: iconSize / 33.4
  Shape {
    visible: root.colorful
    width: 44.4
    height: 33.4
    x: -67.8 * root.colourScale
    y: -4.9 * root.colourScale
    transform: Scale { xScale: root.colourScale; yScale: root.colourScale }
    preferredRendererType: Shape.CurveRenderer
    opacity: root.dim

    ShapePath {
      strokeWidth: -1
      fillGradient: LinearGradient {
        x1: 67.8462; y1: 30.7545; x2: 111.308; y2: 30.7545
        GradientStop { position: 0.0; color: "#E41F2E" }
        GradientStop { position: 0.22; color: "#E74628" }
        GradientStop { position: 0.39; color: "#EA5F25" }
        GradientStop { position: 0.5; color: "#EB6824" }
        GradientStop { position: 1.0; color: "#F9B916" }
      }
      PathSvg { path: "M67.9316 34.7935C67.8782 34.8454 67.8462 34.9174 67.8462 34.996V34.9987C67.8462 35.1546 67.973 35.2825 68.1304 35.2825C68.1825 35.2825 68.2305 35.2692 68.2719 35.2452L68.2959 35.2239C72.2243 31.6939 78.6706 26.7728 87.1078 27.1952C90.3824 27.3578 93.3514 28.3905 96.0575 29.9363C98.845 31.5287 104.08 36.8096 104.08 36.8096C104.927 37.6745 106.116 38.2182 107.412 38.2262C107.412 38.2262 108.162 38.2115 108.805 38.005C108.993 37.945 109.076 37.9103 109.076 37.9103C109.441 37.7571 111.592 36.711 111.275 33.9993C111.145 32.8972 110.598 31.7805 109.564 30.7851C109.337 30.5666 101.831 22.0955 87.5322 23.424C78.1489 24.7033 71.6145 30.4773 67.9316 34.7935Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillGradient: LinearGradient {
        x1: 67.8462; y1: 31.7139; x2: 75.7897; y2: 31.7139
        GradientStop { position: 0.0; color: "#95C13D" }
        GradientStop { position: 0.13; color: "#8CBE3D" }
        GradientStop { position: 0.33; color: "#73B940" }
        GradientStop { position: 0.59; color: "#4BAF44" }
        GradientStop { position: 0.89; color: "#15A349" }
        GradientStop { position: 1.0; color: "#009E4C" }
      }
      PathSvg { path: "M68.408 35.056C68.3813 35.1852 68.2665 35.2825 68.1304 35.2825C67.9743 35.2825 67.8462 35.1559 67.8462 34.9987C67.8462 34.9987 67.8462 34.9747 67.8489 34.9627C68.0063 32.8039 71.7466 12.497 75.7817 37.8144C75.7817 37.8144 75.787 37.8637 75.7897 37.8983C75.7937 37.9636 75.775 38.0249 75.775 38.0249C75.7337 38.1862 75.5735 38.2315 75.4428 38.2008C75.3347 38.1755 75.2466 38.0982 75.2226 37.9823C75.2226 37.9823 73.2517 28.2785 71.0874 28.3865C70.1587 28.4518 69.4848 30.1441 68.4173 35.0147C68.4146 35.028 68.4093 35.056 68.4093 35.056H68.408Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillGradient: LinearGradient {
        x1: 75.2199; y1: 23.1136; x2: 112.109; y2: 23.1136
        GradientStop { position: 0.0; color: "#21A6DF" }
        GradientStop { position: 0.22; color: "#158FCE" }
        GradientStop { position: 0.48; color: "#0B7ABF" }
        GradientStop { position: 0.75; color: "#056EB6" }
        GradientStop { position: 1.0; color: "#036AB4" }
      }
      PathSvg { path: "M111.923 31.9631C111.654 30.8131 105.849 4.90008 92.0303 8.30878C88.8812 9.08433 86.4473 11.8054 84.4644 14.4412C79.1269 21.5451 75.9778 34.9214 75.2319 37.8544C75.1839 38.0396 75.2973 38.1689 75.4427 38.2022C75.5735 38.2329 75.7323 38.1876 75.775 38.0263C76.1833 36.4552 77.3162 32.6334 77.8606 31.125C79.6326 26.0332 84.9248 16.6959 90.6692 16.7519C98.2498 16.8239 101.886 30.8465 102.917 34.7549C103.414 36.7284 105.266 38.2155 107.414 38.2275C109.994 38.2369 112.098 36.1607 112.11 33.5809C112.11 33.365 112.089 32.6614 111.924 31.9631H111.923Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: "#21A6DF"
      PathSvg { path: "M110.864 33.5396C110.855 35.4598 109.29 37.0069 107.367 36.9989C105.444 36.9883 103.895 35.4252 103.904 33.5076C103.914 31.5874 105.479 30.0376 107.4 30.0483C109.325 30.0563 110.874 31.6207 110.863 33.5396H110.864Z" }
    }
  }
}
