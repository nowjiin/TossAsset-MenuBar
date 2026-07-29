#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

// 앱 아이콘 생성기.
//
//   swift Scripts/make-icon.swift            → Resources/AppIcon.icns
//   swift Scripts/make-icon.swift out.icns   → 지정 경로
//
// 결과물(.icns)은 커밋한다. 빌드마다 다시 만들 이유가 없고, Scripts/build-app.sh 는 복사만 한다.
// 디자인을 바꿨을 때만 다시 실행한다.
//
// 토스 로고·브랜드 마크는 쓰지 않는다. 등록 상표이고, 비공식 앱이 공식으로 오인된다.
//
// 크기별로 그리는 내용이 다르다. 16px 에서 메뉴바 띠와 메뉴 이름까지 넣으면 얼룩이 되므로
// 작은 크기에서는 요소를 덜어낸다 — 작은 아이콘의 규칙은 더하기가 아니라 빼기다.

// MARK: - 팔레트

struct RGB {
    let r, g, b: CGFloat
    func cg(_ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
}

let skyBlue = RGB(r: 0.29, g: 0.60, b: 0.98)
let deepBlue = RGB(r: 0.11, g: 0.31, b: 0.71)
let white = RGB(r: 1, g: 1, b: 1)

// MARK: - 도형

/// macOS 아이콘 관례의 라운드 사각형. 모서리 반경은 변 길이의 22.37%.
func squirclePath(in rect: CGRect) -> CGPath {
    CGPath(
        roundedRect: rect,
        cornerWidth: rect.width * 0.2237,
        cornerHeight: rect.height * 0.2237,
        transform: nil
    )
}

/// 캔버스 안쪽 여백. macOS 아이콘은 캔버스를 꽉 채우지 않는다.
func iconBox(_ size: CGFloat) -> CGRect {
    let inset = size * 0.09
    return CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
}

func drawBackground(_ ctx: CGContext, _ box: CGRect) {
    ctx.saveGState()
    ctx.addPath(squirclePath(in: box))
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [skyBlue.cg(), deepBlue.cg()] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: box.minX, y: box.maxY),
        end: CGPoint(x: box.maxX, y: box.minY),
        options: []
    )
    ctx.restoreGState()
}

/// 상단의 메뉴바 띠.
///
/// 실제 메뉴바 배치를 그대로 옮긴다: 앱 상태 아이콘은 **오른쪽 끝**, 메뉴 이름은 왼쪽.
/// 신호등(창 버튼)을 넣지 않는 이유가 여기 있다 — 넣으면 창 타이틀바로 읽힌다.
func drawMenuBar(_ ctx: CGContext, _ box: CGRect, _ size: CGFloat, ratio: CGFloat, details: Bool) {
    let stripHeight = box.height * ratio
    let strip = CGRect(x: box.minX, y: box.maxY - stripHeight, width: box.width, height: stripHeight)

    ctx.saveGState()
    ctx.addPath(squirclePath(in: box))
    ctx.clip()
    // 어두운 띠가 다크 모드 메뉴바를 연상시키고, 파란 본체와 대비도 크다.
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.fill(strip)
    ctx.setFillColor(white.cg(0.20))
    ctx.fill(CGRect(x: strip.minX, y: strip.minY, width: strip.width, height: max(1, size * 0.008)))
    ctx.restoreGState()

    guard details else { return }

    // 오른쪽 끝의 상승 사선 — 이 앱이 메뉴바에서 차지하는 자리.
    let glyph = stripHeight * 0.52
    let center = CGPoint(x: strip.maxX - box.width * 0.11, y: strip.midY)
    ctx.saveGState()
    ctx.setStrokeColor(white.cg(0.95))
    ctx.setLineWidth(size * 0.021)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: center.x - glyph * 0.5, y: center.y - glyph * 0.42))
    ctx.addLine(to: CGPoint(x: center.x + glyph * 0.5, y: center.y + glyph * 0.42))
    ctx.strokePath()
    ctx.restoreGState()

    // 왼쪽의 짧은 선 두 개 — 메뉴 이름.
    ctx.saveGState()
    ctx.setFillColor(white.cg(0.30))
    var x = strip.minX + box.width * 0.10
    for width in [box.width * 0.085, box.width * 0.06] {
        ctx.addPath(CGPath(
            roundedRect: CGRect(
                x: x, y: strip.midY - size * 0.008,
                width: width, height: size * 0.016
            ),
            cornerWidth: size * 0.008, cornerHeight: size * 0.008, transform: nil
        ))
        ctx.fillPath()
        x += width + box.width * 0.045
    }
    ctx.restoreGState()
}

/// 본문: 배경 막대 + 상승 화살표.
/// 화살표는 꺾임 없는 직선이다. 꺾으면 16px 에서 형태가 사라진다.
func drawContent(_ ctx: CGContext, _ box: CGRect, _ size: CGFloat, topRatio: CGFloat, bars: Bool) {
    let area = CGRect(
        x: box.minX, y: box.minY,
        width: box.width, height: box.height * (1 - topRatio)
    )

    if bars {
        let heights: [CGFloat] = [0.30, 0.46, 0.64]
        let barWidth = area.width * 0.135
        let gap = area.width * 0.075
        let totalWidth = barWidth * 3 + gap * 2
        var x = area.midX - totalWidth / 2 - area.width * 0.03
        let baseline = area.minY + area.height * 0.20

        for height in heights {
            let rect = CGRect(x: x, y: baseline, width: barWidth, height: area.height * height)
            ctx.saveGState()
            // 낮은 알파로 깔아 화살표를 방해하지 않게 한다.
            ctx.setFillColor(white.cg(0.32))
            ctx.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: barWidth * 0.36, cornerHeight: barWidth * 0.36,
                transform: nil
            ))
            ctx.fillPath()
            ctx.restoreGState()
            x += barWidth + gap
        }
    }

    let points = [
        CGPoint(x: 0.20, y: 0.36),
        CGPoint(x: 0.74, y: 0.80),
    ].map { CGPoint(x: area.minX + area.width * $0.x, y: area.minY + area.height * $0.y) }

    ctx.saveGState()
    ctx.setStrokeColor(white.cg())
    ctx.setLineWidth(size * 0.088)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: points[0])
    ctx.addLine(to: points[1])
    ctx.strokePath()
    ctx.restoreGState()

    let tip = points[1]
    let arrow = size * 0.16
    ctx.saveGState()
    ctx.setFillColor(white.cg())
    ctx.beginPath()
    ctx.move(to: CGPoint(x: tip.x + arrow * 0.28, y: tip.y + arrow * 0.28))
    ctx.addLine(to: CGPoint(x: tip.x + arrow * 0.28, y: tip.y - arrow * 0.68))
    ctx.addLine(to: CGPoint(x: tip.x - arrow * 0.68, y: tip.y + arrow * 0.28))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}

/// 얼마나 그릴지. **픽셀 크기가 아니라 슬롯(pt) 기준**으로 정한다.
///
/// 픽셀 크기로 판단하면 같은 슬롯의 1x 와 2x 가 서로 다른 그림이 된다
/// (32pt 슬롯: 1x=32px 는 띠 없음, 2x=64px 는 띠 있음). Retina 여부로 아이콘 구조가
/// 달라지는 건 버그다. 한 슬롯은 한 디자인이어야 한다.
enum Detail {
    /// 16pt·32pt 슬롯. 띠와 메뉴 이름을 빼고 화살표·막대만 남긴다.
    case minimal
    /// 128pt 이상. 전체 디자인.
    case full
}

func drawIcon(_ ctx: CGContext, _ size: CGFloat, _ detail: Detail) {
    let box = iconBox(size)
    drawBackground(ctx, box)

    switch detail {
    case .full:
        let ratio: CGFloat = 0.185
        drawContent(ctx, box, size, topRatio: ratio, bars: true)
        drawMenuBar(ctx, box, size, ratio: ratio, details: true)
    case .minimal:
        drawContent(ctx, box, size, topRatio: 0, bars: true)
    }
}

// MARK: - 출력

func render(size: CGFloat, detail: Detail) -> CGImage {
    let pixels = Int(size)
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    // 크기별로 새로 그린다. 큰 이미지를 줄이면 작은 크기에서 선이 흐려진다.
    drawIcon(ctx, size, detail)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 대상을 만들 수 없습니다: \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG 저장 실패: \(url.path)"])
    }
}

/// iconutil 이 요구하는 파일명 규약. detail 은 슬롯(pt) 단위로 묶는다.
let iconsetEntries: [(name: String, size: CGFloat, detail: Detail)] = [
    ("icon_16x16.png", 16, .minimal),
    ("icon_16x16@2x.png", 32, .minimal),
    ("icon_32x32.png", 32, .minimal),
    ("icon_32x32@2x.png", 64, .minimal),
    ("icon_128x128.png", 128, .full),
    ("icon_128x128@2x.png", 256, .full),
    ("icon_256x256.png", 256, .full),
    ("icon_256x256@2x.png", 512, .full),
    ("icon_512x512.png", 512, .full),
    ("icon_512x512@2x.png", 1024, .full),
]

let output = URL(
    fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
)

let fileManager = FileManager.default
let workDir = fileManager.temporaryDirectory
    .appendingPathComponent("make-icon-\(ProcessInfo.processInfo.processIdentifier)")
let iconset = workDir.appendingPathComponent("AppIcon.iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: workDir) }

for entry in iconsetEntries {
    try writePNG(
        render(size: entry.size, detail: entry.detail),
        to: iconset.appendingPathComponent(entry.name)
    )
}
print("▸ iconset \(iconsetEntries.count)개 렌더링")

try fileManager.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("오류: iconutil 실패 (\(iconutil.terminationStatus))")
    exit(1)
}

let bytes = (try? fileManager.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("✓ \(output.path) (\(bytes) bytes)")
