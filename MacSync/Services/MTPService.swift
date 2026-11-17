import Foundation
import AppKit
import os

// MARK: - Progress Relay Context (Thread-Safe with OSAllocatedUnfairLock)
private final class ProgressRelay: @unchecked Sendable {
    let continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    let fileName: String
    let direction: TransferDirection
    let destinationURL: URL?

    private struct State {
        var isCancelled: Bool = false
        var lastYieldTime: Double = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation,
        fileName: String,
        direction: TransferDirection,
        destinationURL: URL? = nil
    ) {
        self.continuation = continuation
        self.fileName = fileName
        self.direction = direction
        self.destinationURL = destinationURL
    }

    var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    func cancel() {
        state.withLock { $0.isCancelled = true }
    }

    func shouldYield(sent: UInt64, total: UInt64, now: Double) -> Bool {
        state.withLock { s in
            if sent == 0 || (total > 0 && sent >= total) || (now - s.lastYieldTime) >= 0.04 {
                s.lastYieldTime = now
                return true
            }
            return false
        }
    }
}

// Global C callback for libmtp transfers
private func mtpProgressCallback(sent: UInt64, total: UInt64, data: UnsafeRawPointer?) -> Int32 {
    guard let data = data else { return 0 }
    let relay = Unmanaged<ProgressRelay>.fromOpaque(data).takeUnretainedValue()
    if relay.isCancelled {
        return 1 // Non-zero return aborts libmtp transfer immediately
    }
    let now = ProcessInfo.processInfo.systemUptime
    // Yield first packet, 100% packet, or throttle to ~25fps (every 40ms) to keep UI responsive
    if relay.shouldYield(sent: sent, total: total, now: now) {
        let fraction = total > 0 ? Double(sent) / Double(total) : 0.0
        relay.continuation.yield(
            TransferProgress(
                bytesTransferred: sent,
                totalBytes: total,
                fractionCompleted: fraction,
                fileName: relay.fileName,
                direction: relay.direction
            )
        )
    }
    return 0
}

// MARK: - MTP Service Actor
public actor MTPService {
    public static let rootFolderId: UInt32 = 0xFFFFFFFF

    private var device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>? = nil
    private var isInitialized: Bool = false
    private let activeRelayLock = OSAllocatedUnfairLock<ProgressRelay?>(initialState: nil)

    public nonisolated func cancelActiveTransfer() {
        activeRelayLock.withLock { relay in
            relay?.cancel()
        }
    }

    public init() {}

    deinit {
        if let dev = device {
            LIBMTP_Release_Device(dev)
        }
    }

    // MARK: - Subsystem Initialization
    private func ensureInitialized() {
        if !isInitialized {
            LIBMTP_Init()
            isInitialized = true
        }
    }

    // MARK: - Conflict Detection
    public func detectConflictingProcesses() -> [String] {
        let conflictingNames: Set<String> = [
            "PTPCamera",
            "Image Capture",
            "Android File Transfer",
            "Android File Transfer Agent",
            "Preview",
            "Dropbox",
            "SmartSwitch",
            "OpenMTP"
        ]

        let conflictingBundles: Set<String> = [
            "com.google.android.mtpagent",
            "com.apple.Image_Capture",
            "com.apple.Preview",
            "com.getdropbox.dropbox",
            "io.ganeshrvel.openmtp"
        ]

        var found = Set<String>()

        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, conflictingNames.contains(name) {
                found.insert(name)
            }
            if let bundleID = app.bundleIdentifier, conflictingBundles.contains(bundleID) {
                found.insert(app.localizedName ?? bundleID)
            }
        }

        if isProcessRunningInKernel(named: "PTPCamera") {
            found.insert("PTPCamera")
        }

        return Array(found).sorted()
    }

    private func isProcessRunningInKernel(named targetName: String) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return false }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return false }

        for proc in procs {
            var kp = proc.kp_proc
            let name = withUnsafePointer(to: &kp.p_comm) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: ptr)) { cStr in
                    String(cString: cStr)
                }
            }
            if name.caseInsensitiveCompare(targetName) == .orderedSame {
                return true
            }
        }
        return false
    }

    public func killConflictingProcesses() {
        let conflicts = detectConflictingProcesses()
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, conflicts.contains(name) {
                app.terminate()
            }
        }

        if conflicts.contains("PTPCamera") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["-9", "PTPCamera"]
            try? task.run()
            task.waitUntilExit()
        }
    }

    // MARK: - Device Connection
    public func isDeviceConnected() -> Bool {
        return device != nil
    }

    public func connect(force: Bool = false) throws -> MTPDeviceInfo {
        ensureInitialized()

        if !force, let currentDev = device {
            return try readDeviceInfo(from: currentDev)
        }

        if let existing = device {
            LIBMTP_Release_Device(existing)
            self.device = nil
        }

        var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>? = nil
        var numRawDevices: Int32 = 0
        let detectErr = LIBMTP_Detect_Raw_Devices(&rawDevices, &numRawDevices)

        guard detectErr == LIBMTP_ERROR_NONE, numRawDevices > 0, let rawList = rawDevices else {
            if rawDevices != nil {
                free(rawDevices)
            }
            let conflicts = detectConflictingProcesses()
            if !conflicts.isEmpty {
                throw MTPError.deviceLockedByProcess(processes: conflicts)
            }
            throw MTPError.deviceNotFound
        }

        defer {
            free(rawDevices)
        }

        guard let openedDevice = LIBMTP_Open_Raw_Device_Uncached(&rawList[0]) else {
            let conflicts = detectConflictingProcesses()
            if !conflicts.isEmpty {
                throw MTPError.deviceLockedByProcess(processes: conflicts)
            }
            throw MTPError.connectionFailed(
                reason: "Could not open MTP device. Ensure your phone screen is unlocked and USB configuration is set to 'File Transfer (MTP)'."
            )
        }

        self.device = openedDevice
        return try readDeviceInfo(from: openedDevice)
    }

    public func disconnect() {
        if let dev = device {
            LIBMTP_Release_Device(dev)
            self.device = nil
        }
    }

    // MARK: - Metadata Inspection
    private func readDeviceInfo(from dev: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) throws -> MTPDeviceInfo {
        var friendlyName = "Android Device"
        if let cFriendly = LIBMTP_Get_Friendlyname(dev) {
            friendlyName = String(cString: cFriendly)
            free(cFriendly)
        }

        var manufacturer = "Unknown"
        if let cMan = LIBMTP_Get_Manufacturername(dev) {
            manufacturer = String(cString: cMan)
            free(cMan)
        }

        var modelName = "Unknown"
        if let cModel = LIBMTP_Get_Modelname(dev) {
            modelName = String(cString: cModel)
            free(cModel)
        }

        var serialNumber = UUID().uuidString
        if let cSerial = LIBMTP_Get_Serialnumber(dev) {
            serialNumber = String(cString: cSerial)
            free(cSerial)
        }

        var maxBattery: UInt8 = 100
        var currentBattery: UInt8 = 100
        LIBMTP_Get_Batterylevel(dev, &maxBattery, &currentBattery)

        var storages: [MTPStorage] = []
        var storageNode = dev.pointee.storage
        while let s = storageNode {
            let storageId = s.pointee.id
            let desc = s.pointee.StorageDescription != nil ? String(cString: s.pointee.StorageDescription) : "Internal Storage"
            let vol = s.pointee.VolumeIdentifier != nil ? String(cString: s.pointee.VolumeIdentifier) : ""
            let maxCap = s.pointee.MaxCapacity
            let freeSpace = s.pointee.FreeSpaceInBytes

            storages.append(
                MTPStorage(
                    id: storageId,
                    storageDescription: desc.isEmpty ? "Internal Storage" : desc,
                    volumeIdentifier: vol,
                    maxCapacity: maxCap,
                    freeSpaceInBytes: freeSpace
                )
            )
            storageNode = s.pointee.next
        }

        return MTPDeviceInfo(
            id: serialNumber,
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            serialNumber: serialNumber,
            currentBattery: Int(currentBattery),
            maxBattery: Int(maxBattery),
            storages: storages
        )
    }

    // MARK: - Directory Listing
    public func listFiles(storageId: UInt32, parentId: UInt32) throws -> [MTPItem] {
        guard let dev = device else {
            throw MTPError.noDeviceConnected
        }

        let fileListHead = LIBMTP_Get_Files_And_Folders(dev, storageId, parentId)
        var items: [MTPItem] = []
        var current = fileListHead

        while let node = current {
            let itemId = node.pointee.item_id
            let parent = node.pointee.parent_id
            let storage = node.pointee.storage_id
            let name = node.pointee.filename != nil ? String(cString: node.pointee.filename) : "Unknown"
            let size = node.pointee.filesize
            let modTime = Date(timeIntervalSince1970: TimeInterval(node.pointee.modificationdate))
            let isFolder = (node.pointee.filetype == LIBMTP_FILETYPE_FOLDER)
            let typeRaw = node.pointee.filetype.rawValue

            items.append(
                MTPItem(
                    id: itemId,
                    parentId: parent,
                    storageId: storage,
                    name: name,
                    size: size,
                    modificationDate: modTime,
                    isFolder: isFolder,
                    fileTypeRaw: typeRaw
                )
            )
            current = node.pointee.next
        }

        // Safe recursive deallocation of libmtp linked list
        var nodeToFree = fileListHead
        while let cur = nodeToFree {
            let next = cur.pointee.next
            cur.pointee.next = nil
            LIBMTP_destroy_file_t(cur)
            nodeToFree = next
        }

        return items
    }

    // MARK: - File Operations
    public func createFolder(name: String, parentId: UInt32, storageId: UInt32) throws -> UInt32 {
        guard let dev = device else {
            throw MTPError.noDeviceConnected
        }

        let safeName = FilenameSanitizer.sanitize(name)
        let newFolderId = safeName.withCString { cName in
            LIBMTP_Create_Folder(dev, UnsafeMutablePointer(mutating: cName), parentId, storageId)
        }

        guard newFolderId != 0 else {
            throw MTPError.folderCreationFailed(name: safeName)
        }
        return newFolderId
    }

    public func deleteObject(id: UInt32) throws {
        guard let dev = device else {
            throw MTPError.noDeviceConnected
        }

        let status = LIBMTP_Delete_Object(dev, id)
        guard status == 0 else {
            throw MTPError.deleteFailed(id: id)
        }
    }

    public func deleteItemRecursively(item: MTPItem, storageId: UInt32) async throws {
        guard let dev = device else {
            throw MTPError.noDeviceConnected
        }

        if item.isFolder {
            // Delete all children first (Android MTP requires empty folder before folder deletion)
            let children = (try? listFiles(storageId: storageId, parentId: item.id)) ?? []
            for child in children {
                try await deleteItemRecursively(item: child, storageId: storageId)
            }
        }

        let status = LIBMTP_Delete_Object(dev, item.id)
        guard status == 0 else {
            throw MTPError.deleteFailed(id: item.id)
        }
    }

    public func renameObject(item: MTPItem, newName: String) throws {
        guard let dev = device else {
            throw MTPError.noDeviceConnected
        }

        let safeName = FilenameSanitizer.sanitize(newName)

        if item.isFolder {
            guard let folderTree = LIBMTP_Get_Folder_List(dev) else {
                throw MTPError.renameFailed(reason: "Could not fetch folder hierarchy")
            }
            defer {
                LIBMTP_destroy_folder_t(folderTree)
            }

            guard let folderNode = LIBMTP_Find_Folder(folderTree, item.id) else {
                throw MTPError.renameFailed(reason: "Target folder node could not be resolved")
            }

            let result = safeName.withCString { cStr in
                LIBMTP_Set_Folder_Name(dev, folderNode, cStr)
            }
            guard result == 0 else {
                throw MTPError.renameFailed(reason: "libmtp returned error code \(result)")
            }
        } else {
            guard let fileStruct = LIBMTP_Get_Filemetadata(dev, item.id) else {
                throw MTPError.renameFailed(reason: "Could not fetch file metadata for ID \(item.id)")
            }
            defer {
                LIBMTP_destroy_file_t(fileStruct)
            }

            let result = safeName.withCString { cStr in
                LIBMTP_Set_File_Name(dev, fileStruct, cStr)
            }
            guard result == 0 else {
                throw MTPError.renameFailed(reason: "libmtp returned error code \(result)")
            }
        }
    }

    // MARK: - Streaming Downloads
    public func downloadFile(
        itemId: UInt32,
        fileName: String,
        destinationURL: URL
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TransferProgress.self, throwing: Error.self)
        Task { [weak self] in
            guard let self = self else {
                continuation.finish(throwing: MTPError.noDeviceConnected)
                return
            }
            await self.executeDownload(
                itemId: itemId,
                fileName: fileName,
                destinationURL: destinationURL,
                continuation: continuation
            )
        }
        return stream
    }

    private func executeDownload(
        itemId: UInt32,
        fileName: String,
        destinationURL: URL,
        continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) {
        guard let dev = self.device else {
            continuation.finish(throwing: MTPError.noDeviceConnected)
            return
        }

        let relay = ProgressRelay(
            continuation: continuation,
            fileName: fileName,
            direction: .download,
            destinationURL: destinationURL
        )
        self.activeRelayLock.withLock { $0 = relay }
        defer { self.activeRelayLock.withLock { $0 = nil } }

        let unmanagedRelay = Unmanaged.passRetained(relay)

        let cPath = destinationURL.path(percentEncoded: false)
        let result = cPath.withCString { cStr in
            LIBMTP_Get_File_To_File(
                dev,
                itemId,
                cStr,
                mtpProgressCallback,
                unmanagedRelay.toOpaque()
            )
        }

        unmanagedRelay.release()

        if relay.isCancelled {
            // Delete partial downloaded file on cancel
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            continuation.finish(throwing: MTPError.transferCancelled)
        } else if result == 0 {
            continuation.finish()
        } else {
            continuation.finish(throwing: MTPError.transferFailed(reason: "Download error code \(result)"))
        }
    }

    // MARK: - Streaming Uploads
    public func uploadFile(
        sourceURL: URL,
        sanitizedFileName: String,
        parentFolderId: UInt32,
        storageId: UInt32
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TransferProgress.self, throwing: Error.self)
        Task { [weak self] in
            guard let self = self else {
                continuation.finish(throwing: MTPError.noDeviceConnected)
                return
            }
            await self.executeUpload(
                sourceURL: sourceURL,
                sanitizedFileName: sanitizedFileName,
                parentFolderId: parentFolderId,
                storageId: storageId,
                continuation: continuation
            )
        }
        return stream
    }

    private func executeUpload(
        sourceURL: URL,
        sanitizedFileName: String,
        parentFolderId: UInt32,
        storageId: UInt32,
        continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) {
        guard let dev = self.device else {
            continuation.finish(throwing: MTPError.noDeviceConnected)
            return
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path(percentEncoded: false)),
              let fileSize = attributes[.size] as? UInt64 else {
            continuation.finish(throwing: MTPError.transferFailed(reason: "Cannot read local file metadata"))
            return
        }

        guard let fileStruct = LIBMTP_new_file_t() else {
            continuation.finish(throwing: MTPError.transferFailed(reason: "Failed to allocate MTP file structure"))
            return
        }
        defer {
            LIBMTP_destroy_file_t(fileStruct)
        }

        fileStruct.pointee.filesize = fileSize
        fileStruct.pointee.filename = strdup(sanitizedFileName)
        fileStruct.pointee.parent_id = parentFolderId
        fileStruct.pointee.storage_id = storageId
        fileStruct.pointee.filetype = self.mapExtensionToFileType(filename: sanitizedFileName)

        let relay = ProgressRelay(
            continuation: continuation,
            fileName: sanitizedFileName,
            direction: .upload
        )
        self.activeRelayLock.withLock { $0 = relay }
        defer { self.activeRelayLock.withLock { $0 = nil } }

        let unmanagedRelay = Unmanaged.passRetained(relay)

        let cPath = sourceURL.path(percentEncoded: false)
        let result = cPath.withCString { cStr in
            LIBMTP_Send_File_From_File(
                dev,
                cStr,
                fileStruct,
                mtpProgressCallback,
                unmanagedRelay.toOpaque()
            )
        }

        unmanagedRelay.release()

        if relay.isCancelled {
            continuation.finish(throwing: MTPError.transferCancelled)
        } else if result == 0 {
            continuation.finish()
        } else {
            continuation.finish(throwing: MTPError.transferFailed(reason: "Upload error code \(result)"))
        }
    }

    // MARK: - Thumbnail Retrieval
    public func getThumbnail(itemId: UInt32) -> Data? {
        guard let dev = device else { return nil }
        var buffer: UnsafeMutablePointer<UInt8>? = nil
        var size: UInt32 = 0
        let ret = LIBMTP_Get_Thumbnail(dev, itemId, &buffer, &size)
        guard ret == 0, let buf = buffer, size > 0 else {
            if let buf = buffer {
                free(buf)
            }
            return nil
        }
        let data = Data(bytes: buf, count: Int(size))
        free(buf)
        return data
    }

    // MARK: - Battery Level Inspection
    public func getBatteryLevel() -> (max: Int, current: Int)? {
        guard let dev = device else { return nil }
        var maxBat: UInt8 = 0
        var curBat: UInt8 = 0
        let ret = LIBMTP_Get_Batterylevel(dev, &maxBat, &curBat)
        guard ret == 0 else { return nil }
        return (max: Int(maxBat), current: Int(curBat))
    }

    // MARK: - File Type Mapping
    private func mapExtensionToFileType(filename: String) -> LIBMTP_filetype_t {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "wav": return LIBMTP_FILETYPE_WAV
        case "mp3": return LIBMTP_FILETYPE_MP3
        case "wma": return LIBMTP_FILETYPE_WMA
        case "ogg": return LIBMTP_FILETYPE_OGG
        case "mp4", "m4v": return LIBMTP_FILETYPE_MP4
        case "wmv": return LIBMTP_FILETYPE_WMV
        case "avi": return LIBMTP_FILETYPE_AVI
        case "mov", "qt": return LIBMTP_FILETYPE_QT
        case "jpg", "jpeg": return LIBMTP_FILETYPE_JPEG
        case "tiff", "tif": return LIBMTP_FILETYPE_TIFF
        case "bmp": return LIBMTP_FILETYPE_BMP
        case "gif": return LIBMTP_FILETYPE_GIF
        case "png": return LIBMTP_FILETYPE_PNG
        case "txt": return LIBMTP_FILETYPE_TEXT
        case "html", "htm": return LIBMTP_FILETYPE_HTML
        case "doc", "docx": return LIBMTP_FILETYPE_DOC
        case "xml": return LIBMTP_FILETYPE_XML
        case "xls", "xlsx": return LIBMTP_FILETYPE_XLS
        case "ppt", "pptx": return LIBMTP_FILETYPE_PPT
        default: return LIBMTP_FILETYPE_UNKNOWN
        }
    }
}
