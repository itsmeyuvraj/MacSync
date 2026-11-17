import Foundation
import SwiftUI
import Observation
import ImageIO

@Observable
@MainActor
public final class AppViewModel {
    // MARK: - Singleton Instance
    public static let shared = AppViewModel()

    // MARK: - Dependencies
    private let mtpService = MTPService()
    private let localService = LocalFileService.shared

    // MARK: - Device & Connection State
    public var deviceInfo: MTPDeviceInfo?
    public var selectedStorage: MTPStorage?
    public var isConnecting: Bool = false
    public var errorMessage: String?
    public var conflictingProcesses: [String] = []

    // MARK: - Transfer Progress State
    public var currentProgress: TransferProgress?
    public var isTransferring: Bool = false

    // MARK: - Local Mac Pane State
    public var currentLocalURL: URL
    public var localBreadcrumbs: [URL] = []
    public var localItems: [LocalFileItem] = []
    public var localSelection: Set<URL> = []
    public var localSearchText: String = ""
    public var localSortOrder: [KeyPathComparator<LocalFileItem>] = [
        KeyPathComparator(\.name, order: .forward)
    ]

    // MARK: - Android MTP Pane State
    public var currentAndroidFolderId: UInt32 = MTPService.rootFolderId
    public var androidBreadcrumbs: [MTPBreadcrumb] = []
    public var androidItems: [MTPItem] = []
    public var rootFolders: [MTPItem] = []
    public var androidSelection: Set<UInt32> = []
    public var lastAnchorSelectionId: UInt32? = nil
    public var androidSearchText: String = ""
    public var androidSortOrder: [KeyPathComparator<MTPItem>] = [
        KeyPathComparator(\.name, order: .forward)
    ]

    // MARK: - Transfer Conflict Resolution State
    public var activeConflict: TransferConflict? = nil
    public var applyConflictToAll: Bool = false
    private var conflictResolutionContinuation: CheckedContinuation<ConflictAction, Never>? = nil
    private var persistentConflictAction: ConflictAction? = nil

    // MARK: - Sidebar Selection State
    public enum SidebarItem: Hashable, Sendable {
        case storage(UInt32)
        case shortcut(String)
    }

    public var selectedSidebarItem: SidebarItem? = nil

    // MARK: - UI & Layout Mode
    public enum ViewLayout: String, CaseIterable, Identifiable, Sendable {
        case grid = "Grid"
        case list = "List"
        public var id: String { rawValue }
    }

    public enum SortCriteria: String, CaseIterable, Identifiable, Sendable {
        case name = "Name"
        case date = "Date Modified"
        case size = "Size"
        public var id: String { rawValue }
    }

    public var layoutMode: ViewLayout = .grid
    public var sortCriteria: SortCriteria = .name
    public var sortAscending: Bool = true
    public var isDragOverWindow: Bool = false
    public var folderDropTargetId: UInt32? = nil
    public var breadcrumbDropTargetId: UInt32? = nil
    public var shortcutDropTargetName: String? = nil
    public var isSidebarVisible: Bool = true
    public var showDeviceSheet: Bool = false

    // Liquid UI Hover & Interaction State
    public var hoveredItemId: UInt32? = nil
    public var hoveredSidebarKey: String? = nil
    public var hoveredCrumbId: UInt32? = nil

    public var currentDisplayTitle: String {
        if let last = androidBreadcrumbs.last {
            if androidBreadcrumbs.count <= 1 {
                return "All"
            }
            return last.name
        }
        return "All"
    }

    public var currentDisplaySubtitle: String {
        if deviceInfo == nil {
            return "Connect your Android device via USB"
        }
        if androidBreadcrumbs.count <= 1 {
            let count = filteredAndSortedAndroidItems.count
            let itemsStr = "\(count) \(count == 1 ? "item" : "items")"
            if let storage = selectedStorage {
                return "\(itemsStr) • \(storage.formattedFreeSpace) available"
            }
            return "All files and folders on your phone."
        }
        let count = filteredAndSortedAndroidItems.count
        let itemsStr = "\(count) \(count == 1 ? "item" : "items")"
        if let storage = selectedStorage {
            return "\(itemsStr) displayed • \(storage.formattedFreeSpace) available"
        }
        return itemsStr
    }

    // MARK: - Dialog & Modal State
    public var showNewFolderSheet: Bool = false
    public var newFolderNameInput: String = ""
    public var isCreatingAndroidFolder: Bool = true

    public var showRenameSheet: Bool = false
    public var renameTargetName: String = ""
    public var renameItemTarget: MTPItem?

    public init() {
        let initialURL = LocalFileService.shared.downloadsURL
        self.currentLocalURL = initialURL
        rebuildLocalBreadcrumbs(for: initialURL)
        refreshLocalDirectory()
    }

    // MARK: - Local Pane Filtering & Sorting
    public var filteredAndSortedLocalItems: [LocalFileItem] {
        let filtered = localSearchText.isEmpty
            ? localItems
            : localItems.filter { $0.name.localizedCaseInsensitiveContains(localSearchText) }

        return filtered.sorted(using: localSortOrder)
    }

    // MARK: - Android Pane Filtering & Sorting
    public var filteredAndSortedAndroidItems: [MTPItem] {
        let filtered = androidSearchText.isEmpty
            ? androidItems
            : androidItems.filter { $0.name.localizedCaseInsensitiveContains(androidSearchText) }

        return filtered.sorted { a, b in
            if a.isFolder != b.isFolder {
                return a.isFolder && !b.isFolder
            }
            switch sortCriteria {
            case .name:
                return sortAscending
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.name.localizedStandardCompare(b.name) == .orderedDescending
            case .date:
                return sortAscending ? a.modificationDate < b.modificationDate : a.modificationDate > b.modificationDate
            case .size:
                return sortAscending ? a.size < b.size : a.size > b.size
            }
        }
    }

    // MARK: - macOS Selection Helpers (Single, Cmd+Click, Shift+Click)
    public func selectSingle(_ id: UInt32) {
        androidSelection = [id]
        lastAnchorSelectionId = id
    }

    public func toggleSelection(for id: UInt32) {
        if androidSelection.contains(id) {
            androidSelection.remove(id)
        } else {
            androidSelection.insert(id)
            lastAnchorSelectionId = id
        }
    }

    public func selectRange(to targetId: UInt32) {
        let items = filteredAndSortedAndroidItems
        guard let targetIndex = items.firstIndex(where: { $0.id == targetId }) else {
            selectSingle(targetId)
            return
        }
        let anchorIndex = items.firstIndex(where: { $0.id == lastAnchorSelectionId }) ?? targetIndex
        let start = min(anchorIndex, targetIndex)
        let end = max(anchorIndex, targetIndex)
        let rangeIds = items[start...end].map { $0.id }
        androidSelection.formUnion(rangeIds)
    }

    // MARK: - Conflict Resolution Helpers
    public func resolveConflict(action: ConflictAction) {
        if applyConflictToAll {
            self.persistentConflictAction = action
        }
        self.activeConflict = nil
        let cont = self.conflictResolutionContinuation
        self.conflictResolutionContinuation = nil
        cont?.resume(returning: action)
    }

    private func requestConflictResolution(for conflict: TransferConflict) async -> ConflictAction {
        if applyConflictToAll, let persistent = persistentConflictAction {
            return persistent
        }
        return await withCheckedContinuation { continuation in
            self.activeConflict = conflict
            self.conflictResolutionContinuation = continuation
        }
    }

    public static func generateUniqueFileName(baseName: String, existingNames: Set<String>) -> String {
        let ns = baseName as NSString
        let ext = ns.pathExtension
        let nameWithoutExt = ns.deletingPathExtension
        var counter = 1
        var candidate = baseName
        while existingNames.contains(candidate.lowercased()) {
            if ext.isEmpty {
                candidate = "\(nameWithoutExt) (\(counter))"
            } else {
                candidate = "\(nameWithoutExt) (\(counter)).\(ext)"
            }
            counter += 1
        }
        return candidate
    }

    // MARK: - Device Connection Operations
    public func connectDevice() async {
        guard deviceInfo == nil && !isConnecting else { return }
        isConnecting = true
        errorMessage = nil

        do {
            let info = try await mtpService.connect()
            self.deviceInfo = info
            self.conflictingProcesses = []

            if let firstStorage = info.storages.first {
                self.selectedStorage = firstStorage
                self.selectedSidebarItem = .storage(firstStorage.id)
                self.currentAndroidFolderId = MTPService.rootFolderId
                self.androidBreadcrumbs = [
                    MTPBreadcrumb(id: MTPService.rootFolderId, name: "All")
                ]
                await refreshAndroidDirectory()
            }
            startBatteryPolling()
        } catch let error as MTPError {
            if case .deviceLockedByProcess(let procs) = error {
                self.conflictingProcesses = procs
            }
            self.errorMessage = error.localizedDescription
            self.deviceInfo = nil
            self.selectedStorage = nil
            self.androidItems = []
        } catch {
            self.errorMessage = error.localizedDescription
            self.deviceInfo = nil
            self.selectedStorage = nil
            self.androidItems = []
        }

        isConnecting = false
    }

    public func killConflictsAndReconnect() async {
        await disconnectDevice()
        await mtpService.killConflictingProcesses()
        conflictingProcesses = []
        await connectDevice()
    }

    public func disconnectDevice() async {
        stopBatteryPolling()
        await mtpService.disconnect()
        self.deviceInfo = nil
        self.selectedStorage = nil
        self.androidItems = []
        self.rootFolders = []
        self.thumbnailCache = [:]
        self.androidBreadcrumbs = []
        self.androidSelection = []
    }

    // MARK: - Live Battery Monitoring
    private var batteryPollingTask: Task<Void, Never>?

    public func startBatteryPolling() {
        stopBatteryPolling()
        batteryPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Poll every 10 seconds
                guard let self = self, self.deviceInfo != nil else { break }
                if !self.isTransferring {
                    await self.refreshBatteryLevel()
                }
            }
        }
    }

    public func stopBatteryPolling() {
        batteryPollingTask?.cancel()
        batteryPollingTask = nil
    }

    public func refreshBatteryLevel() async {
        guard !isTransferring else { return }
        guard let (maxBat, curBat) = await mtpService.getBatteryLevel(),
              let currentInfo = self.deviceInfo else { return }

        if currentInfo.currentBattery != curBat || currentInfo.maxBattery != maxBat {
            self.deviceInfo = MTPDeviceInfo(
                id: currentInfo.id,
                friendlyName: currentInfo.friendlyName,
                manufacturer: currentInfo.manufacturer,
                modelName: currentInfo.modelName,
                serialNumber: currentInfo.serialNumber,
                currentBattery: curBat,
                maxBattery: maxBat,
                storages: currentInfo.storages,
                isCharging: currentInfo.isCharging
            )
        }
    }

    public func navigateToRoot() async {
        guard let storage = selectedStorage else { return }
        self.selectedSidebarItem = .storage(storage.id)
        self.currentAndroidFolderId = MTPService.rootFolderId
        self.androidBreadcrumbs = [
            MTPBreadcrumb(id: MTPService.rootFolderId, name: "All")
        ]
        await refreshAndroidDirectory()
    }

    public func switchStorage(_ storage: MTPStorage) async {
        guard storage.id != selectedStorage?.id else { return }
        self.selectedStorage = storage
        self.selectedSidebarItem = .storage(storage.id)
        self.currentAndroidFolderId = MTPService.rootFolderId
        self.androidBreadcrumbs = [
            MTPBreadcrumb(id: MTPService.rootFolderId, name: "All")
        ]
        await refreshAndroidDirectory()
    }

    public func navigateToFolderItem(_ folder: MTPItem) async {
        guard selectedStorage != nil else { return }
        self.currentAndroidFolderId = folder.id
        self.androidBreadcrumbs = [
            MTPBreadcrumb(id: MTPService.rootFolderId, name: "All"),
            MTPBreadcrumb(id: folder.id, name: folder.name)
        ]
        await refreshAndroidDirectory()
    }

    public func handleSidebarSelection(_ item: SidebarItem?) async {
        guard let item = item else { return }
        self.selectedSidebarItem = item
        switch item {
        case .storage(let id):
            if let matched = deviceInfo?.storages.first(where: { $0.id == id }) {
                await switchStorage(matched)
            }
        case .shortcut(let folderName):
            await navigateToShortcut(named: folderName)
        }
    }

    // MARK: - Local Navigation
    public func navigateToLocalURL(_ url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            currentLocalURL = url
            rebuildLocalBreadcrumbs(for: url)
            refreshLocalDirectory()
        }
    }

    public func refreshLocalDirectory() {
        do {
            localItems = try localService.listDirectory(at: currentLocalURL)
            localSelection.removeAll()
        } catch {
            errorMessage = "Failed to read local folder: \(error.localizedDescription)"
        }
    }

    private func rebuildLocalBreadcrumbs(for url: URL) {
        var crumbs: [URL] = []
        var current = url
        while current.path != "/" && current.pathComponents.count > 1 {
            crumbs.insert(current, at: 0)
            current = current.deletingLastPathComponent()
        }
        crumbs.insert(URL(fileURLWithPath: "/"), at: 0)
        localBreadcrumbs = crumbs
    }

    // MARK: - Android Navigation
    public func openAndroidFolder(_ item: MTPItem) async {
        guard item.isFolder else { return }
        currentAndroidFolderId = item.id
        androidBreadcrumbs.append(MTPBreadcrumb(id: item.id, name: item.name))
        await refreshAndroidDirectory()
    }

    public func navigateAndroidBreadcrumb(_ crumb: MTPBreadcrumb) async {
        guard let index = androidBreadcrumbs.firstIndex(where: { $0.id == crumb.id }) else { return }
        androidBreadcrumbs = Array(androidBreadcrumbs.prefix(through: index))
        currentAndroidFolderId = crumb.id
        await refreshAndroidDirectory()
    }

    public func navigateToShortcut(named folderName: String) async {
        guard let storage = selectedStorage else { return }

        // Start search from root
        do {
            let rootItems = try await mtpService.listFiles(
                storageId: storage.id,
                parentId: MTPService.rootFolderId
            )
            if let matched = rootItems.first(where: { $0.isFolder && $0.name.caseInsensitiveCompare(folderName) == .orderedSame }) {
                currentAndroidFolderId = matched.id
                androidBreadcrumbs = [
                    MTPBreadcrumb(id: MTPService.rootFolderId, name: "All"),
                    MTPBreadcrumb(id: matched.id, name: matched.name)
                ]
                await refreshAndroidDirectory()
            } else {
                errorMessage = "Directory '\(folderName)' not found on \(storage.storageDescription)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refreshAndroidDirectory() async {
        guard let storage = selectedStorage else { return }
        do {
            androidItems = try await mtpService.listFiles(
                storageId: storage.id,
                parentId: currentAndroidFolderId
            )
            if currentAndroidFolderId == MTPService.rootFolderId {
                self.rootFolders = androidItems.filter { $0.isFolder }.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            } else if rootFolders.isEmpty {
                Task {
                    if let rootList = try? await self.mtpService.listFiles(storageId: storage.id, parentId: MTPService.rootFolderId) {
                        self.rootFolders = rootList.filter { $0.isFolder }.sorted {
                            $0.name.localizedStandardCompare($1.name) == .orderedAscending
                        }
                    }
                }
            }
            androidSelection.removeAll()
            await refreshBatteryLevel()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Android Operations (Folder, Rename, Delete)
    public func createAndroidFolder(name: String) async {
        guard let storage = selectedStorage, !name.isEmpty else { return }
        do {
            _ = try await mtpService.createFolder(
                name: name,
                parentId: currentAndroidFolderId,
                storageId: storage.id
            )
            await refreshAndroidDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func renameAndroidItem(_ item: MTPItem, to newName: String) async {
        guard !newName.isEmpty, newName != item.name else { return }
        do {
            try await mtpService.renameObject(item: item, newName: newName)
            await refreshAndroidDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSelectedAndroidItems() async {
        guard !androidSelection.isEmpty else { return }
        do {
            for itemId in androidSelection {
                try await mtpService.deleteObject(id: itemId)
            }
            await refreshAndroidDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Breadcrumb and Navigation
    public var canNavigateUp: Bool {
        return androidBreadcrumbs.count > 1
    }

    public func navigateUp() async {
        guard androidBreadcrumbs.count > 1 else { return }
        androidBreadcrumbs.removeLast()
        if let parent = androidBreadcrumbs.last {
            currentAndroidFolderId = parent.id
            await refreshAndroidDirectory()
        }
    }

    // MARK: - Transfer Auto-Dismissal
    private var dismissProgressTask: Task<Void, Never>?

    public func scheduleProgressDismissal(delaySeconds: Double = 3.5) {
        dismissProgressTask?.cancel()
        dismissProgressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.currentProgress = nil
            }
        }
    }

    // MARK: - File Transfers (Upload & Download)
    public func uploadDroppedItems(urls: [URL], targetFolderId: UInt32? = nil) async {
        guard let storage = selectedStorage else {
            errorMessage = "No Android storage selected for upload."
            return
        }

        let destinationFolderId = targetFolderId ?? currentAndroidFolderId

        dismissProgressTask?.cancel()
        applyConflictToAll = false
        persistentConflictAction = nil
        activeConflict = nil
        isTransferring = true
        var lastCompletedFileName = ""
        var lastCompletedSize: UInt64 = 0

        for fileURL in urls {
            guard isTransferring else { break }
            do {
                try await uploadRecursive(url: fileURL, parentFolderId: destinationFolderId, storageId: storage.id)
                lastCompletedFileName = fileURL.lastPathComponent
                if let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let sz = attr[.size] as? UInt64 {
                    lastCompletedSize = sz
                }
            } catch {
                if isTransferring {
                    self.errorMessage = "Upload failed: \(error.localizedDescription)"
                }
                break
            }
        }

        if let last = currentProgress {
            let finalBytes = last.totalBytes > 0 ? last.totalBytes : (lastCompletedSize > 0 ? lastCompletedSize : last.bytesTransferred)
            self.currentProgress = TransferProgress(
                bytesTransferred: finalBytes,
                totalBytes: finalBytes,
                fractionCompleted: 1.0,
                fileName: last.fileName,
                direction: .upload,
                isCompleted: true
            )
            scheduleProgressDismissal()
        } else if !lastCompletedFileName.isEmpty {
            self.currentProgress = TransferProgress(
                bytesTransferred: lastCompletedSize,
                totalBytes: lastCompletedSize,
                fractionCompleted: 1.0,
                fileName: lastCompletedFileName,
                direction: .upload,
                isCompleted: true
            )
            scheduleProgressDismissal()
        } else {
            self.currentProgress = nil
        }

        isTransferring = false
        await refreshAndroidDirectory()
    }

    public func uploadDroppedItemsToShortcut(urls: [URL], folderName: String) async {
        guard let storage = selectedStorage else { return }
        do {
            let rootItems = try await mtpService.listFiles(
                storageId: storage.id,
                parentId: MTPService.rootFolderId
            )
            if let matched = rootItems.first(where: { $0.isFolder && $0.name.caseInsensitiveCompare(folderName) == .orderedSame }) {
                await uploadDroppedItems(urls: urls, targetFolderId: matched.id)
            } else {
                await uploadDroppedItems(urls: urls)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadRecursive(url: URL, parentFolderId: UInt32, storageId: UInt32) async throws {
        guard isTransferring else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }

        let safeName = FilenameSanitizer.sanitize(url.lastPathComponent)

        if isDir.boolValue {
            // Check if folder already exists at parentFolderId
            let targetItems = (parentFolderId == currentAndroidFolderId)
                ? androidItems
                : (try? await mtpService.listFiles(storageId: storageId, parentId: parentFolderId)) ?? []
            let existingFolder = targetItems.first(where: { $0.isFolder && $0.name.caseInsensitiveCompare(safeName) == .orderedSame })

            let targetFolderId: UInt32
            if let existing = existingFolder {
                targetFolderId = existing.id
            } else {
                targetFolderId = try await mtpService.createFolder(
                    name: safeName,
                    parentId: parentFolderId,
                    storageId: storageId
                )
            }

            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in contents {
                guard isTransferring else { break }
                try await uploadRecursive(url: child, parentFolderId: targetFolderId, storageId: storageId)
            }
        } else {
            // Check for file conflict at destination
            let targetItems = (parentFolderId == currentAndroidFolderId)
                ? androidItems
                : (try? await mtpService.listFiles(storageId: storageId, parentId: parentFolderId)) ?? []
            let existingFile = targetItems.first(where: { !$0.isFolder && $0.name.caseInsensitiveCompare(safeName) == .orderedSame })

            var uploadFileName = safeName
            if let existing = existingFile {
                let localSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64)
                let conflict = TransferConflict(
                    fileName: safeName,
                    destinationPath: "Android Device",
                    existingFileSize: existing.size,
                    newFileSize: localSize,
                    direction: .upload
                )
                let action = await requestConflictResolution(for: conflict)
                guard isTransferring else { return }

                switch action {
                case .skip:
                    return
                case .replace:
                    try? await mtpService.deleteObject(id: existing.id)
                    uploadFileName = safeName
                case .keepBoth:
                    let existingNames = Set(targetItems.map { $0.name.lowercased() })
                    uploadFileName = Self.generateUniqueFileName(baseName: safeName, existingNames: existingNames)
                }
            }

            let stream = await mtpService.uploadFile(
                sourceURL: url,
                sanitizedFileName: uploadFileName,
                parentFolderId: parentFolderId,
                storageId: storageId
            )
            for try await progress in stream {
                guard isTransferring else { break }
                self.currentProgress = progress
            }
        }
    }

    public func downloadSelectedAndroidItems(to targetDirectory: URL? = nil) async {
        let selectedItems = androidItems.filter { androidSelection.contains($0.id) && !$0.isFolder }
        guard !selectedItems.isEmpty else { return }

        let destDir = targetDirectory ?? LocalFileService.shared.downloadsURL

        dismissProgressTask?.cancel()
        applyConflictToAll = false
        persistentConflictAction = nil
        activeConflict = nil
        isTransferring = true
        var lastCompletedItem: MTPItem?

        for item in selectedItems {
            guard isTransferring else { break }
            var destURL = destDir.appendingPathComponent(item.name)

            if FileManager.default.fileExists(atPath: destURL.path) {
                let localSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? UInt64)
                let conflict = TransferConflict(
                    fileName: item.name,
                    destinationPath: destDir.path,
                    existingFileSize: localSize,
                    newFileSize: item.size,
                    direction: .download
                )
                let action = await requestConflictResolution(for: conflict)
                guard isTransferring else { break }

                switch action {
                case .skip:
                    continue
                case .replace:
                    try? FileManager.default.removeItem(at: destURL)
                case .keepBoth:
                    let localFiles = (try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? []
                    let existingNames = Set(localFiles.map { $0.lowercased() })
                    let uniqueName = Self.generateUniqueFileName(baseName: item.name, existingNames: existingNames)
                    destURL = destDir.appendingPathComponent(uniqueName)
                }
            }

            do {
                let stream = await mtpService.downloadFile(
                    itemId: item.id,
                    fileName: item.name,
                    destinationURL: destURL
                )

                for try await progress in stream {
                    guard isTransferring else { break }
                    self.currentProgress = progress
                }
                lastCompletedItem = item
            } catch {
                if isTransferring {
                    self.errorMessage = "Download failed for '\(item.name)': \(error.localizedDescription)"
                }
                break
            }
        }

        if let last = currentProgress {
            let finalBytes = last.totalBytes > 0 ? last.totalBytes : (lastCompletedItem?.size ?? last.bytesTransferred)
            self.currentProgress = TransferProgress(
                bytesTransferred: finalBytes,
                totalBytes: finalBytes,
                fractionCompleted: 1.0,
                fileName: last.fileName,
                direction: .download,
                isCompleted: true
            )
            scheduleProgressDismissal()
        } else if let item = lastCompletedItem {
            self.currentProgress = TransferProgress(
                bytesTransferred: item.size,
                totalBytes: item.size,
                fractionCompleted: 1.0,
                fileName: item.name,
                direction: .download,
                isCompleted: true
            )
            scheduleProgressDismissal()
        } else {
            self.currentProgress = nil
        }

        isTransferring = false
        refreshLocalDirectory()
    }

    public nonisolated func startDragDownload(
        item: MTPItem,
        completion: @Sendable @escaping (URL?, Bool, Error?) -> Void
    ) -> Progress {
        let systemProgress = Progress(totalUnitCount: Int64(max(1, item.size)))

        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSyncDragExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let destURL = exportDir.appendingPathComponent(item.name)

        if FileManager.default.fileExists(atPath: destURL.path),
           let attr = try? FileManager.default.attributesOfItem(atPath: destURL.path),
           let fSize = attr[.size] as? UInt64, fSize == item.size {
            systemProgress.completedUnitCount = Int64(item.size)
            completion(destURL, true, nil)
            return systemProgress
        }

        let service = self.mtpService
        Task { @MainActor in
            self.dismissProgressTask?.cancel()
            self.isTransferring = true
            self.currentProgress = TransferProgress(
                bytesTransferred: 0,
                totalBytes: item.size,
                fractionCompleted: 0.0,
                fileName: item.name,
                direction: .download
            )
        }

        Task {
            do {
                let stream = await service.downloadFile(
                    itemId: item.id,
                    fileName: item.name,
                    destinationURL: destURL
                )
                for try await p in stream {
                    systemProgress.completedUnitCount = Int64(p.bytesTransferred)
                    await MainActor.run {
                        self.currentProgress = p
                    }
                }
                await MainActor.run {
                    self.currentProgress = TransferProgress(
                        bytesTransferred: item.size,
                        totalBytes: item.size,
                        fractionCompleted: 1.0,
                        fileName: item.name,
                        direction: .download,
                        isCompleted: true
                    )
                    self.isTransferring = false
                    self.refreshLocalDirectory()
                    self.scheduleProgressDismissal()
                }
                completion(destURL, true, nil)
            } catch {
                await MainActor.run {
                    self.currentProgress = nil
                    self.isTransferring = false
                    self.errorMessage = "Copy to Mac failed: \(error.localizedDescription)"
                }
                completion(nil, true, error)
            }
        }

        return systemProgress
    }

    public nonisolated func prepareLocalCopyForDrag(item: MTPItem) -> URL? {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSyncDragExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let destURL = exportDir.appendingPathComponent(item.name)

        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL
        }
        return nil
    }

    public func cancelTransfer() {
        dismissProgressTask?.cancel()
        mtpService.cancelActiveTransfer()
        currentProgress = nil
        isTransferring = false
    }

    // MARK: - Quick Look Preview
    public func previewSelectedItem() async {
        guard let selectedId = androidSelection.first,
              let item = androidItems.first(where: { $0.id == selectedId }),
              !item.isFolder else {
            return
        }

        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacSyncPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let localPreviewURL = cacheDir.appendingPathComponent("\(item.id)_\(item.name)")

        if FileManager.default.fileExists(atPath: localPreviewURL.path) {
            QuickLookController.shared.togglePreview(for: localPreviewURL)
            return
        }

        dismissProgressTask?.cancel()
        isTransferring = true
        do {
            let stream = await mtpService.downloadFile(
                itemId: item.id,
                fileName: item.name,
                destinationURL: localPreviewURL
            )
            for try await progress in stream {
                self.currentProgress = progress
            }
            self.currentProgress = TransferProgress(
                bytesTransferred: item.size,
                totalBytes: item.size,
                fractionCompleted: 1.0,
                fileName: item.name,
                direction: .download,
                isCompleted: true
            )
            isTransferring = false
            scheduleProgressDismissal(delaySeconds: 2.0)
            QuickLookController.shared.togglePreview(for: localPreviewURL)
        } catch {
            currentProgress = nil
            isTransferring = false
            errorMessage = "Quick Look download failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Thumbnail Cache & Loading
    public var thumbnailCache: [UInt32: NSImage] = [:]
    private var loadingThumbnails: Set<UInt32> = []

    public func requestThumbnail(for item: MTPItem) async {
        guard item.isImage else { return }
        guard thumbnailCache[item.id] == nil, !loadingThumbnails.contains(item.id) else { return }

        loadingThumbnails.insert(item.id)
        defer { loadingThumbnails.remove(item.id) }

        // 1. Check disk thumbnail cache
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacSyncThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let thumbURL = cacheDir.appendingPathComponent("\(item.id).jpg")

        if let diskImg = NSImage(contentsOf: thumbURL) {
            thumbnailCache[item.id] = diskImg
            return
        }

        // 2. Check if full file was already downloaded by QuickLook
        let previewDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacSyncPreview", isDirectory: true)
        let previewURL = previewDir.appendingPathComponent("\(item.id)_\(item.name)")
        if FileManager.default.fileExists(atPath: previewURL.path),
           let fullImg = NSImage(contentsOf: previewURL) {
            thumbnailCache[item.id] = fullImg
            return
        }

        // 3. Ask MTP service for hardware/EXIF thumbnail
        if let thumbData = await mtpService.getThumbnail(itemId: item.id),
           let img = NSImage(data: thumbData) {
            try? thumbData.write(to: thumbURL)
            thumbnailCache[item.id] = img
            return
        }

        // 4. Fallback for images < 4 MB: download and downsample
        if item.size > 0 && item.size < 4 * 1024 * 1024 {
            let tempURL = cacheDir.appendingPathComponent("temp_\(item.id)_\(item.name)")
            do {
                let stream = await mtpService.downloadFile(itemId: item.id, fileName: item.name, destinationURL: tempURL)
                for try await _ in stream {}
                if let generated = createThumbnail(from: tempURL, maxPixelSize: 180) {
                    thumbnailCache[item.id] = generated
                    if let tData = generated.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tData),
                       let jpegData = bitmap.representation(using: .jpeg, properties: [:]) {
                        try? jpegData.write(to: thumbURL)
                    }
                }
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                // Silently skip if download fails
            }
        }
    }

    private func createThumbnail(from url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgThumb, size: NSSize(width: maxPixelSize, height: maxPixelSize))
    }
}
