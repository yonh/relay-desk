// Run from flutter_app: swift tool/extract_logos.swift
// Extract the user's selected spherical marks without regenerating their art.
import Cocoa
import ImageIO
import UniformTypeIdentifiers

let sourceURL = URL(fileURLWithPath: "design/planet-logos/selected-source.png")
let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let selections: [(String, CGRect)] = [
  ("A1", CGRect(x: 307, y: 27, width: 203, height: 201)),
  ("A2", CGRect(x: 667, y: 28, width: 202, height: 200)),
  ("B1", CGRect(x: 309, y: 282, width: 197, height: 197)),
  ("B2", CGRect(x: 669, y: 283, width: 199, height: 197)),
  ("C1", CGRect(x: 316, y: 530, width: 183, height: 182)),
  ("C3", CGRect(x: 1032, y: 530, width: 192, height: 182)),
]

func render(_ crop: CGImage, size: Int) -> CGImage {
  let context = CGContext(data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.interpolationQuality = .high
  // Same optical scale for all choices; leave transparent icon margins.
  let margin = CGFloat(size) * 0.09
  let rect = CGRect(x: margin, y: margin,
    width: CGFloat(size) - 2 * margin, height: CGFloat(size) - 2 * margin)
  context.addEllipse(in: rect)
  context.clip()
  context.draw(crop, in: rect)
  return context.makeImage()!
}

func save(_ image: CGImage, path: String) {
  let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  precondition(CGImageDestinationFinalize(destination))
}

for (id, rect) in selections {
  if id == "A2" {
    // A2 was replaced with the user's ring-free Mars reference.
    let url = URL(fileURLWithPath: "design/planet-logos/A2-source.png")
    let replacement = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let original = CGImageSourceCreateImageAtIndex(replacement, 0, nil)!
    let context = CGContext(data: nil, width: 1024, height: 1024,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(original, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    save(context.makeImage()!, path: "assets/logos/A2.png")
    continue
  }
  let crop = image.cropping(to: rect)!
  save(render(crop, size: 1024), path: "assets/logos/\(id).png")
  if id == "B2" {
    for size in [16, 32, 64, 128, 256, 512, 1024] {
      save(render(crop, size: size),
        path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(size).png")
    }
  }
}
