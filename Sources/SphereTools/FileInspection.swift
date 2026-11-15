import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Identifies a file from its leading bytes instead of trusting the extension.
enum FileSniffer {
    struct Result {
        var kind: String
        var mime: String
        var isBinary: Bool
        var detail: String?
    }

    static func sniff(_ data: Data) -> Result {
        if data.isEmpty {
            return Result(kind: "empty", mime: "application/x-empty", isBinary: false)
        }
        let bytes = [UInt8](data.prefix(32))
        func starts(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset..<(offset + signature.count)]) == signature
        }

        if starts([0x89, 0x50, 0x4E, 0x47]) {
            return Result(kind: "png", mime: "image/png", isBinary: true)
        }
        if starts([0xFF, 0xD8, 0xFF]) {
            return Result(kind: "jpeg", mime: "image/jpeg", isBinary: true)
        }
        if starts(Array("GIF8".utf8)) {
            return Result(kind: "gif", mime: "image/gif", isBinary: true)
        }
        if starts(Array("%PDF".utf8)) {
            return Result(kind: "pdf", mime: "application/pdf", isBinary: true)
        }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) {
            return Result(kind: "zip", mime: "application/zip", isBinary: true)
        }
        if starts([0x1F, 0x8B]) {
            return Result(kind: "gzip", mime: "application/gzip", isBinary: true)
        }
        if starts(Array("SQLite format 3\0".utf8)) {
            return Result(kind: "sqlite", mime: "application/vnd.sqlite3", isBinary: true)
        }
        if starts(Array("RIFF".utf8)), bytes.count >= 12, Array(bytes[8..<12]) == Array("WEBP".utf8) {
            return Result(kind: "webp", mime: "image/webp", isBinary: true)
        }
        if starts([0x42, 0x4D]) {
            return Result(kind: "bmp", mime: "image/bmp", isBinary: true)
        }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) {
            return Result(kind: "tiff", mime: "image/tiff", isBinary: true)
        }
        if starts([0xFE, 0xED, 0xFA, 0xCE]) || starts([0xCF, 0xFA, 0xED, 0xFE])
            || starts([0xCA, 0xFE, 0xBA, 0xBE]) {
            return Result(kind: "mach-o", mime: "application/x-mach-binary", isBinary: true)
        }
        if starts([0x7F, 0x45, 0x4C, 0x46]) {
            return Result(kind: "elf", mime: "application/x-elf", isBinary: true)
        }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            if ["heic", "heix", "hevc", "mif1", "msf1"].contains(brand) {
                return Result(kind: "heic", mime: "image/heic", isBinary: true)
            }
            if ["avif", "avis"].contains(brand) {
                return Result(kind: "avif", mime: "image/avif", isBinary: true)
            }
            if ["qt  ", "isom", "mp42", "M4V "].contains(brand) {
                return Result(kind: "video", mime: "video/mp4", isBinary: true, detail: "ISO BMFF (\(brand))")
            }
        }
        if starts([0x00, 0x61, 0x73, 0x6D]) {
            return Result(kind: "wasm", mime: "application/wasm", isBinary: true)
        }
        if starts([0xFF, 0xFE]) || starts([0xFE, 0xFF]) {
            return Result(kind: "utf-16 text", mime: "text/plain", isBinary: false)
        }
        if starts([0xEF, 0xBB, 0xBF]) {
            return Result(kind: "utf-8 text (BOM)", mime: "text/plain", isBinary: false)
        }

        if data.contains(0) {
            return Result(kind: "binary", mime: "application/octet-stream", isBinary: true)
        }
        // A high ratio of control bytes also indicates binary data.
        let control = bytes.filter { $0 < 0x09 || ($0 > 0x0D && $0 < 0x20) }.count
        if bytes.count > 0, Double(control) / Double(bytes.count) > 0.2 {
            return Result(kind: "binary", mime: "application/octet-stream", isBinary: true)
        }
        return Result(kind: "text", mime: "text/plain", isBinary: false)
    }

    static func sniff(fileAt url: URL, prefixLength: Int = 8_192) -> Result {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Result(kind: "unreadable", mime: "application/octet-stream", isBinary: true)
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: prefixLength)) ?? Data()
        return sniff(data)
    }
}

enum FileMetadata {
    static func report(path: String, url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = attributes[.type] as? FileAttributeType ?? .typeUnknown
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes[.modificationDate] as? Date
        let created = attributes[.creationDate] as? Date
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let owner = (attributes[.ownerAccountName] as? String) ?? "-"
        let group = (attributes[.groupOwnerAccountName] as? String) ?? "-"

        var lines: [String] = []
        lines.append("path: \(path)")
        lines.append("type: \(typeName(type))")
        lines.append("size: \(size) bytes")
        lines.append("mode: \(String(format: "%04o", permissions)) \(symbolicMode(permissions))")
        lines.append("owner: \(owner):\(group)")
        if let modified { lines.append("mtime: \(iso(modified))") }
        if let created { lines.append("birth: \(iso(created))") }

        if type == .typeRegular {
            let sniffed = FileSniffer.sniff(fileAt: url)
            lines.append("detected: \(sniffed.kind) (\(sniffed.mime))")
            if let detail = sniffed.detail { lines.append("detail: \(detail)") }
        }
        if type == .typeSymbolicLink,
           let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            lines.append("target: \(destination)")
        }
        return lines.joined(separator: "\n")
    }

    static func typeName(_ type: FileAttributeType) -> String {
        switch type {
        case .typeRegular: return "file"
        case .typeDirectory: return "directory"
        case .typeSymbolicLink: return "symlink"
        case .typeCharacterSpecial: return "character device"
        case .typeBlockSpecial: return "block device"
        case .typeSocket: return "socket"
        default: return "unknown"
        }
    }

    static func symbolicMode(_ permissions: Int) -> String {
        let bits: [(Int, String)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return bits.map { permissions & $0.0 != 0 ? $0.1 : "-" }.joined()
    }

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum ImageInspector {
    static func inspect(path: String, url: URL, thumbnail: Bool, thumbnailSize: Int) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            let sniffed = FileSniffer.sniff(fileAt: url)
            return "Not a decodable image.\npath: \(path)\ndetected: \(sniffed.kind) (\(sniffed.mime))"
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
        let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue
        let type = CGImageSourceGetType(source).map { $0 as String } ?? "unknown"
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0

        var lines: [String] = [
            "path: \(path)",
            "format: \(type)",
            "dimensions: \(width)×\(height) px",
            "color depth: \(depth) bit",
            "file size: \(fileSize) bytes",
        ]
        if let orientation { lines.append("orientation: \(orientation)") }
        if let dpiWidth, let dpiHeight { lines.append("dpi: \(Int(dpiWidth))×\(Int(dpiHeight))") }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            var fields: [String] = []
            if let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String { fields.append("date=\(value)") }
            if let value = exif[kCGImagePropertyExifLensModel] as? String { fields.append("lens=\(value)") }
            if let value = exif[kCGImagePropertyExifExposureTime] as? NSNumber { fields.append("exposure=\(value)s") }
            if let value = exif[kCGImagePropertyExifFNumber] as? NSNumber { fields.append("f/\(value)") }
            if let value = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let iso = value.first {
                fields.append("iso=\(iso)")
            }
            if let value = exif[kCGImagePropertyExifFocalLength] as? NSNumber { fields.append("focal=\(value)mm") }
            if !fields.isEmpty { lines.append("exif: " + fields.joined(separator: " · ")) }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            var fields: [String] = []
            if let value = tiff[kCGImagePropertyTIFFMake] as? String { fields.append("make=\(value)") }
            if let value = tiff[kCGImagePropertyTIFFModel] as? String { fields.append("model=\(value)") }
            if let value = tiff[kCGImagePropertyTIFFSoftware] as? String { fields.append("software=\(value)") }
            if !fields.isEmpty { lines.append("camera: " + fields.joined(separator: " · ")) }
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? NSNumber,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? NSNumber {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? ""
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? ""
            lines.append("gps: \(latitude)\(latRef), \(longitude)\(lonRef)")
        }

        if thumbnail {
            lines.append(contentsOf: thumbnailSection(source: source, size: thumbnailSize))
        }
        return lines.joined(separator: "\n")
    }

    private static func thumbnailSection(source: CGImageSource, size: Int) -> [String] {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(32, min(size, 512)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return ["thumbnail: unavailable"]
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return ["thumbnail: unavailable"]
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return ["thumbnail: unavailable"]
        }
        let base64 = (data as Data).base64EncodedString()
        guard base64.count <= 300_000 else {
            return ["thumbnail: \(image.width)×\(image.height) px (encoded thumbnail too large to inline)"]
        }
        return [
            "thumbnail: \(image.width)×\(image.height) px PNG, base64 below",
            "thumbnail_base64: \(base64)",
        ]
    }
}
