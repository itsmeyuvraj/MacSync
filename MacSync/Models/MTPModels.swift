import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Transfer Direction
public enum TransferDirection: String, Sendable, Codable {
    case upload = "Upload"
    case download = "Download"
}

// MARK: - Transfer Conflict Resolution
public enum ConflictAction: String, CaseIterable, Sendable {
    case replace = "Replace"
    case keepBoth = "Keep Both"
    case skip = "Skip"
}

public struct TransferConflict: Identifiable, Sendable {
    public let id = UUID()
    public let fileName: String
    public let destinationPath: String
    public let existingFileSize: UInt64?
    public let newFileSize: UInt64?
    public let direction: TransferDirection

    public init(
        fileName: String,
        destinationPath: String,
        existingFileSize: UInt64?,
        newFileSize: UInt64?,
        direction: TransferDirection
    ) {
        self.fileName = fileName
        self.destinationPath = destinationPath
        self.existingFileSize = existingFileSize
        self.newFileSize = newFileSize
        self.direction = direction
    }
}

// MARK: - Transfer Progress Info
public struct TransferProgress: Sendable {
    public let bytesTransferred: UInt64
    public let totalBytes: UInt64
    public let fractionCompleted: Double
    public let fileName: String
    public let direction: TransferDirection
    public let isCompleted: Bool
    public let errorMessage: String?

    public init(
        bytesTransferred: UInt64,
        totalBytes: UInt64,
        fractionCompleted: Double,
        fileName: String,
        direction: TransferDirection,
        isCompleted: Bool = false,
        errorMessage: String? = nil
    ) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.fractionCompleted = fractionCompleted
        self.fileName = fileName
        self.direction = direction
        self.isCompleted = isCompleted
        self.errorMessage = errorMessage
    }
}

// MARK: - Device Info
public struct MTPDeviceInfo: Identifiable, Sendable {
    public let id: String
    public let friendlyName: String
    public let manufacturer: String
    public let modelName: String
    public let serialNumber: String
    public let currentBattery: Int
    public let maxBattery: Int
    public let storages: [MTPStorage]
    public let isCharging: Bool

    public var batteryPercentage: Double {
        guard maxBattery > 0 else { return 0.0 }
        return Double(currentBattery) / Double(maxBattery)
    }

    public var batteryLevelPercent: Int {
        if maxBattery > 0 && maxBattery != 100 {
            return min(100, max(0, Int((Double(currentBattery) / Double(maxBattery)) * 100.0)))
        }
        return min(100, max(0, currentBattery))
    }

    public var batteryIconName: String {
        let pct = batteryLevelPercent
        if pct >= 85 {
            return "battery.100"
        } else if pct >= 60 {
            return "battery.75"
        } else if pct >= 35 {
            return "battery.50"
        } else {
            return "battery.25"
        }
    }

    public init(
        id: String,
        friendlyName: String,
        manufacturer: String,
        modelName: String,
        serialNumber: String,
        currentBattery: Int,
        maxBattery: Int,
        storages: [MTPStorage],
        isCharging: Bool = true
    ) {
        self.id = id
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.serialNumber = serialNumber
        self.currentBattery = currentBattery
        self.maxBattery = maxBattery
        self.storages = storages
        self.isCharging = isCharging
    }
}

// MARK: - Storage Info
public struct MTPStorage: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let storageDescription: String
    public let volumeIdentifier: String
    public let maxCapacity: UInt64
    public let freeSpaceInBytes: UInt64

    public var usedSpaceInBytes: UInt64 {
        if maxCapacity >= freeSpaceInBytes {
            return maxCapacity - freeSpaceInBytes
        }
        return 0
    }

    public var usedFraction: Double {
        guard maxCapacity > 0 else { return 0.0 }
        return Double(usedSpaceInBytes) / Double(maxCapacity)
    }

    public var formattedCapacity: String {
        ByteCountFormatter.string(fromByteCount: Int64(maxCapacity), countStyle: .file)
    }

    public var formattedFreeSpace: String {
        ByteCountFormatter.string(fromByteCount: Int64(freeSpaceInBytes), countStyle: .file)
    }

    public init(
        id: UInt32,
        storageDescription: String,
        volumeIdentifier: String,
        maxCapacity: UInt64,
        freeSpaceInBytes: UInt64
    ) {
        self.id = id
        self.storageDescription = storageDescription
        self.volumeIdentifier = volumeIdentifier
        self.maxCapacity = maxCapacity
        self.freeSpaceInBytes = freeSpaceInBytes
    }
}

// MARK: - MTP Item Representation
public struct MTPItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UInt32
    public let parentId: UInt32
    public let storageId: UInt32
    public let name: String
    public let size: UInt64
    public let modificationDate: Date
    public let isFolder: Bool
    public let fileTypeRaw: UInt32

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

    public var isImage: Bool {
        if isFolder { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff"].contains(ext)
    }

    public var systemImageName: String {
        if isFolder {
            return "folder.fill"
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff":
            return "photo.fill"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return "film.fill"
        case "mp3", "m4a", "flac", "wav", "ogg", "aac":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "rar", "7z":
            return "archivebox.fill"
        case "apk":
            return "shippingbox.fill"
        case "txt", "md", "json", "xml", "csv":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }

    public var iconTint: (r: Double, g: Double, b: Double) {
        if isFolder {
            return (0.31, 0.61, 0.83) // #4E9CD4 soft cerulean blue
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff":
            return (0.92, 0.48, 0.48) // soft coral / rose
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return (0.72, 0.52, 0.94) // soft lavender
        case "mp3", "m4a", "flac", "wav", "ogg", "aac":
            return (0.94, 0.70, 0.28) // soft warm amber
        case "pdf":
            return (0.92, 0.38, 0.35) // soft crimson
        case "zip", "tar", "gz", "rar", "7z":
            return (0.45, 0.75, 0.65) // soft sage teal
        case "apk":
            return (0.35, 0.78, 0.52) // soft android green
        case "txt", "md", "json", "xml", "csv":
            return (0.42, 0.68, 0.88) // soft sky
        default:
            return (0.65, 0.64, 0.65) // muted warm silver
        }
    }

    public init(
        id: UInt32,
        parentId: UInt32,
        storageId: UInt32,
        name: String,
        size: UInt64,
        modificationDate: Date,
        isFolder: Bool,
        fileTypeRaw: UInt32
    ) {
        self.id = id
        self.parentId = parentId
        self.storageId = storageId
        self.name = name
        self.size = size
        self.modificationDate = modificationDate
        self.isFolder = isFolder
        self.fileTypeRaw = fileTypeRaw
    }
}

extension MTPItem: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Breadcrumb Navigation
public struct MTPBreadcrumb: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String

    public init(id: UInt32, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Error Types
public enum MTPError: LocalizedError, Sendable {
    case deviceLockedByProcess(processes: [String])
    case deviceNotFound
    case connectionFailed(reason: String)
    case storageNotFound
    case itemNotFound(id: UInt32)
    case transferFailed(reason: String)
    case transferCancelled
    case folderCreationFailed(name: String)
    case deleteFailed(id: UInt32)
    case renameFailed(reason: String)
    case invalidFilename(String)
    case noDeviceConnected

    public var errorDescription: String? {
        switch self {
        case .deviceLockedByProcess(let processes):
            let list = processes.joined(separator: ", ")
            return "USB Interface Locked: The following application(s) are claiming exclusive USB MTP ownership: [\(list)]. Close them or terminate PTPCamera to proceed."
        case .deviceNotFound:
            return "No Android device detected on USB. Please connect your device, unlock the screen, and choose 'File Transfer (MTP)' in USB Settings."
        case .connectionFailed(let reason):
            return "Failed to establish MTP connection: \(reason)"
        case .storageNotFound:
            return "Selected storage partition could not be located."
        case .itemNotFound(let id):
            return "Item with ID \(id) not found on device."
        case .transferFailed(let reason):
            return "File transfer failed: \(reason)"
        case .transferCancelled:
            return "File transfer was cancelled."
        case .folderCreationFailed(let name):
            return "Failed to create folder '\(name)' on Android device."
        case .deleteFailed(let id):
            return "Failed to delete item #\(id) from Android device."
        case .renameFailed(let reason):
            return "Failed to rename item: \(reason)"
        case .invalidFilename(let reason):
            return "Invalid filename: \(reason)"
        case .noDeviceConnected:
            return "No active MTP device session."
        }
    }
}

// MARK: - Filename Sanitizer
public enum FilenameSanitizer {
    public static func sanitize(_ filename: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: ":?*\"<>|/\\")
        var sanitized = filename.components(separatedBy: illegalCharacters).joined(separator: "_")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if sanitized.isEmpty {
            sanitized = "unnamed_file"
        }
        if sanitized.utf8.count > 255 {
            sanitized = String(sanitized.prefix(250))
        }
        return sanitized
    }
}
