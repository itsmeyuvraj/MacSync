import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Local File Item
public struct LocalFileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isFolder: Bool
    public let size: UInt64
    public let modificationDate: Date

    public var formattedSize: String {
        if isFolder {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }

    public var systemImageName: String {
        if isFolder {
            return "folder.fill"
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp":
            return "photo.fill"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return "film.fill"
        case "mp3", "m4a", "flac", "wav", "ogg", "aac":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "rar", "7z":
            return "archivebox.fill"
        case "txt", "md", "json", "swift", "c", "h", "xml":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }
}

// MARK: - Local File Service
public final class LocalFileService: Sendable {
    public static let shared = LocalFileService()

    public var homeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public var desktopURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? homeURL
    }

    public var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? homeURL
    }

    public var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? homeURL
    }

    public func listDirectory(at url: URL) throws -> [LocalFileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var items: [LocalFileItem] = []
        for fileURL in contents {
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            let isDir = values.isDirectory ?? false
            let size = UInt64(values.fileSize ?? 0)
            let date = values.contentModificationDate ?? Date()

            items.append(
                LocalFileItem(
                    url: fileURL,
                    name: fileURL.lastPathComponent,
                    isFolder: isDir,
                    size: size,
                    modificationDate: date
                )
            )
        }
        return items
    }

    public func createFolder(at parentURL: URL, name: String) throws -> URL {
        let safeName = FilenameSanitizer.sanitize(name)
        let target = parentURL.appendingPathComponent(safeName, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    public func deleteItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
