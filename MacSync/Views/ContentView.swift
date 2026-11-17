import SwiftUI
import UniformTypeIdentifiers

// MARK: - Window Accessor for Modern Borderless macOS Window Dragging
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.isOpaque = false
                // Exact warm dark background matching reference #252324 with 0.98 alpha for subtle liquid depth
                window.backgroundColor = NSColor(calibratedRed: 37/255.0, green: 35/255.0, blue: 36/255.0, alpha: 0.98)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Modern Tactile Manila Folder View (Non-Blue Folder Design)
struct ModernFolderIconView: View {
    let isTarget: Bool
    let size: CGFloat

    // Warm Manila / Amber Palette (replaces generic blue)
    private let tabColor = Color(red: 0.94, green: 0.74, blue: 0.36)       // #F0BD5C
    private let frontTop = Color(red: 0.96, green: 0.80, blue: 0.44)       // #F5CC70
    private let frontBottom = Color(red: 0.86, green: 0.63, blue: 0.24)    // #DCA13D
    private let targetGreen = Color(red: 0.22, green: 0.82, blue: 0.44)    // #38D170

    var body: some View {
        if isTarget {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [targetGreen, Color(red: 0.16, green: 0.68, blue: 0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: targetGreen.opacity(0.4), radius: 6, y: 2)
        } else {
            ZStack(alignment: .leading) {
                // Back Folder Tab
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: max(2, size * 0.08), style: .continuous)
                        .fill(tabColor)
                        .frame(width: size * 0.44, height: size * 0.22)
                        .offset(x: size * 0.04, y: size * 0.04)
                    Spacer()
                }
                .frame(width: size * 1.05, height: size * 0.84)

                // Front Folder Body with subtle rim highlight
                RoundedRectangle(cornerRadius: max(3, size * 0.14), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [frontTop, frontBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 1.05, height: size * 0.74)
                    .offset(y: size * 0.07)
                    .overlay(
                        RoundedRectangle(cornerRadius: max(3, size * 0.14), style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.black.opacity(0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                            .offset(y: size * 0.07)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 3, y: 2)
            }
            .frame(width: size * 1.08, height: size)
        }
    }
}

@MainActor
public struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public init() {
        self.viewModel = AppViewModel.shared
    }

    // MARK: - Exact Colors Measured Directly From Reference App Image
    // Backgrounds:
    private let sidebarBg = Color(red: 49/255.0, green: 45/255.0, blue: 44/255.0)     // #312D2C warm espresso dark charcoal
    private let detailBg = Color(red: 37/255.0, green: 35/255.0, blue: 36/255.0)       // #252324 warm matte graphite charcoal
    private let itemSelectedBg = Color.white.opacity(0.08)
    private let itemHoverBg = Color.white.opacity(0.045)

    // Icons exact color matching:
    private let blueAccent = Color(red: 85/255.0, green: 149/255.0, blue: 195/255.0)   // #5595C3 soft cerulean blue ("All")
    private let goldAccent = Color(red: 198/255.0, green: 180/255.0, blue: 104/255.0)  // #C6B468 soft canary gold
    private let greenAccent = Color(red: 89/255.0, green: 153/255.0, blue: 100/255.0)  // #599964 soft meadow green
    private let folderMuted = Color(red: 141/255.0, green: 137/255.0, blue: 138/255.0) // #8D898A warm taupe gray

    // Typography exact color matching:
    private let textPrimary = Color(white: 0.96)                                         // #F5F5F5 pure bold title
    private let textSecondary = Color(red: 145/255.0, green: 143/255.0, blue: 144/255.0)// #918F90 warm silver subtitle
    private let textSidebar = Color(red: 216/255.0, green: 214/255.0, blue: 215/255.0)  // #D8D6D7 sidebar item & settings text
    private let sectionHeaderColor = Color(red: 109/255.0, green: 105/255.0, blue: 104/255.0) // #6D6968 (.folders label)

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar (Liquid Design)
            if viewModel.isSidebarVisible {
                sidebarView
                    .frame(width: 220)
                    .background(
                        ZStack {
                            sidebarBg
                            // Specular top edge gradient for liquid depth
                            LinearGradient(
                                colors: [Color.white.opacity(0.025), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    )

                // Hairline divider with subtle depth
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 1)
            }

            // MARK: - Main Detail Content (Liquid Design)
            mainDetailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailBg)
        }
        .frame(minWidth: 840, minHeight: 540)
        .background(WindowAccessor())
        .preferredColorScheme(.dark)
        // Global Drag-and-Drop Destination (uploads into current active folder)
        .dropDestination(for: URL.self) { urls, _ in
            if viewModel.folderDropTargetId == nil && viewModel.breadcrumbDropTargetId == nil && viewModel.shortcutDropTargetName == nil {
                Task {
                    await viewModel.uploadDroppedItems(urls: urls)
                }
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.25)) {
                viewModel.isDragOverWindow = targeted
            }
        }
        .task {
            guard viewModel.deviceInfo == nil && !viewModel.isConnecting else { return }
            await viewModel.connectDevice()
        }
        // Keyboard Shortcuts
        .onKeyPress(.space) {
            Task { await viewModel.previewSelectedItem() }
            return .handled
        }
        .onKeyPress(.delete) {
            Task { await viewModel.deleteSelectedAndroidItems() }
            return .handled
        }
        // Sheets & Dialogs
        .sheet(isPresented: $viewModel.showNewFolderSheet) {
            newFolderSheet
        }
        .sheet(isPresented: $viewModel.showRenameSheet) {
            renameSheet
        }
        .sheet(isPresented: $viewModel.showDeviceSheet) {
            deviceInfoSheet
        }
        .sheet(item: $viewModel.activeConflict) { conflict in
            conflictResolutionSheet(conflict: conflict)
        }
        .alert("Notice", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Liquid Sidebar View
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Window Traffic Light Space & Sidebar Toggle Icon
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        viewModel.isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textSidebar)
                        .padding(5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(red: 86/255.0, green: 82/255.0, blue: 81/255.0).opacity(0.45))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar")
            }
            .padding(.top, 18)
            .padding(.trailing, 14)
            .padding(.bottom, 12)
            .padding(.leading, 74) // Leaves generous breathing room for macOS traffic lights

            // Primary Navigation Item (All)
            VStack(alignment: .leading, spacing: 3) {
                sidebarItemRow(
                    title: "All",
                    icon: "folder.fill",
                    color: blueAccent,
                    selectionKey: "all"
                ) {
                    Task { await viewModel.navigateToRoot() }
                }
            }
            .padding(.horizontal, 10)

            // Section Header: .folders (Real Folders From Connected Phone)
            Text(".folders")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(sectionHeaderColor)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 4)

            // Real Folders from Connected Phone
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !viewModel.rootFolders.isEmpty {
                        ForEach(viewModel.rootFolders) { folder in
                            let visuals = folderVisuals(for: folder.name)
                            sidebarFolderRow(folder: folder, icon: visuals.icon, color: visuals.color)
                        }
                    } else if viewModel.deviceInfo != nil {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading folders...")
                                .font(.system(size: 12))
                                .foregroundColor(textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    } else {
                        // Helpful placeholders when phone is not yet connected
                        ForEach(["DCIM", "Download", "Pictures", "Documents", "Music"], id: \.self) { name in
                            let visuals = folderVisuals(for: name)
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.clear)
                                    .frame(width: 3, height: 14)

                                Image(systemName: visuals.icon)
                                    .font(.system(size: 13))
                                    .foregroundColor(visuals.color.opacity(0.4))
                                    .frame(width: 18)

                                Text(name)
                                    .font(.system(size: 13))
                                    .foregroundColor(textSidebar.opacity(0.4))

                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: .infinity)

            // Section Header: .storage (Storage Partitions & Live Capacity)
            Text(".storage")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(sectionHeaderColor)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 4) {
                if let device = viewModel.deviceInfo {
                    ForEach(device.storages) { storage in
                        sidebarStorageRow(storage: storage)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13))
                            .foregroundColor(folderMuted)
                        Text("No Storage")
                            .font(.system(size: 13))
                            .foregroundColor(textSidebar.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Spacer()

            // Bottom Footer (Settings on left, live battery status on right)
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(height: 1)

            HStack {
                Button {
                    viewModel.showDeviceSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                        Text("Settings")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(textSidebar)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.02))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                if let device = viewModel.deviceInfo {
                    let isCharging = device.isCharging
                    let batteryColor = isCharging
                        ? Color(red: 0.22, green: 0.82, blue: 0.44) // #38D170 vibrant charging green
                        : textSidebar

                    HStack(spacing: 3) {
                        if isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(batteryColor)
                        }
                        Image(systemName: device.batteryIconName)
                            .font(.system(size: 11, weight: isCharging ? .medium : .regular))
                            .foregroundColor(batteryColor)

                        Text("\(device.batteryLevelPercent)%")
                            .font(.system(size: 11, weight: isCharging ? .medium : .regular).monospacedDigit())
                            .foregroundColor(batteryColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isCharging ? batteryColor.opacity(0.14) : Color.white.opacity(0.04))
                            .overlay(
                                Capsule().stroke(isCharging ? batteryColor.opacity(0.28) : Color.clear, lineWidth: 0.5)
                            )
                    )
                } else {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10))
                        .foregroundColor(textSecondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func sidebarItemRow(
        title: String,
        icon: String,
        color: Color,
        selectionKey: String,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = (selectionKey == "all" && viewModel.androidBreadcrumbs.count <= 1)
            || (viewModel.shortcutDropTargetName == selectionKey)

        let isHovered = (viewModel.hoveredSidebarKey == selectionKey)
        let isDropTarget = (viewModel.shortcutDropTargetName == selectionKey)

        return Button(action: action) {
            HStack(spacing: 9) {
                // Liquid leading selection capsule indicator
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? color : Color.clear)
                    .frame(width: 3, height: 14)

                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : textSidebar)

                Spacer()

                if isDropTarget {
                    Text("Drop")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(blueAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(blueAccent.opacity(0.2))
                        )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isDropTarget ? blueAccent.opacity(0.20) :
                        (isSelected ? itemSelectedBg : (isHovered ? itemHoverBg : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isDropTarget ? blueAccent :
                                (isSelected ? Color.white.opacity(0.06) : Color.clear),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            viewModel.hoveredSidebarKey = hovering ? selectionKey : nil
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                if selectionKey == "all" {
                    await viewModel.uploadDroppedItems(urls: urls)
                } else {
                    await viewModel.uploadDroppedItemsToShortcut(urls: urls, folderName: selectionKey)
                }
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.2)) {
                viewModel.shortcutDropTargetName = targeted ? selectionKey : nil
            }
        }
    }

    private func sidebarStorageRow(storage: MTPStorage) -> some View {
        let isSelected = (viewModel.selectedStorage?.id == storage.id && viewModel.androidBreadcrumbs.count <= 1)
        let isTarget = (viewModel.folderDropTargetId == storage.id)
        let isHovered = (viewModel.hoveredSidebarKey == "storage_\(storage.id)")

        return Button {
            Task { await viewModel.switchStorage(storage) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: isTarget ? "folder.badge.plus" : "folder.fill")
                        .font(.system(size: 13))
                        .foregroundColor(isTarget ? blueAccent : folderMuted)
                        .frame(width: 16)

                    Text(storage.storageDescription)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white : textSidebar)
                        .lineLimit(1)

                    Spacer()

                    Text(storage.formattedFreeSpace)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(textSecondary)
                }

                // Fluid liquid storage progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3.5)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [blueAccent, Color(red: 0.45, green: 0.72, blue: 0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, storage.usedFraction))), height: 3.5)
                    }
                }
                .frame(height: 3.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isTarget ? blueAccent.opacity(0.18) :
                        (isSelected ? itemSelectedBg : (isHovered ? itemHoverBg : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isTarget ? blueAccent : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            viewModel.hoveredSidebarKey = hovering ? "storage_\(storage.id)" : nil
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                await viewModel.uploadDroppedItems(urls: urls, targetFolderId: MTPService.rootFolderId)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.2)) {
                viewModel.folderDropTargetId = targeted ? storage.id : nil
            }
        }
    }

    private func folderVisuals(for name: String) -> (icon: String, color: Color) {
        let lower = name.lowercased()
        switch lower {
        case "dcim", "camera":
            return ("camera.fill", goldAccent)
        case "download", "downloads":
            return ("arrow.down.circle.fill", greenAccent)
        case "pictures", "photos":
            return ("photo.on.rectangle.angled", Color(red: 0.92, green: 0.48, blue: 0.48))
        case "movies", "video", "videos":
            return ("film.fill", Color(red: 0.72, green: 0.52, blue: 0.94))
        case "music", "audio", "songs":
            return ("music.note", Color(red: 0.96, green: 0.55, blue: 0.30))
        case "documents", "docs":
            return ("doc.text.fill", Color(red: 0.35, green: 0.72, blue: 0.92))
        case "android":
            return ("gearshape.2.fill", Color(white: 0.52))
        case "podcasts":
            return ("antenna.radiowaves.left.and.right", Color(red: 0.75, green: 0.55, blue: 0.90))
        case "ringtones", "notifications", "alarms":
            return ("bell.fill", Color(red: 0.94, green: 0.75, blue: 0.25))
        default:
            return ("folder.fill", folderMuted)
        }
    }

    private func sidebarFolderRow(folder: MTPItem, icon: String, color: Color) -> some View {
        let isSelected = (viewModel.currentAndroidFolderId == folder.id)
            || (viewModel.androidBreadcrumbs.last?.id == folder.id)
        let isHovered = (viewModel.hoveredSidebarKey == "folder_\(folder.id)")
        let isDropTarget = (viewModel.folderDropTargetId == folder.id)

        return Button {
            Task { await viewModel.navigateToFolderItem(folder) }
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? color : Color.clear)
                    .frame(width: 3, height: 14)

                Image(systemName: isDropTarget ? "folder.badge.plus" : icon)
                    .font(.system(size: 13))
                    .foregroundColor(isDropTarget ? blueAccent : color)
                    .frame(width: 18)

                Text(folder.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : textSidebar)
                    .lineLimit(1)

                Spacer()

                if isDropTarget {
                    Text("Drop")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(blueAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(blueAccent.opacity(0.2)))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isDropTarget ? blueAccent.opacity(0.20) :
                        (isSelected ? itemSelectedBg : (isHovered ? itemHoverBg : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isDropTarget ? blueAccent :
                                (isSelected ? Color.white.opacity(0.06) : Color.clear),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            viewModel.hoveredSidebarKey = hovering ? "folder_\(folder.id)" : nil
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                await viewModel.uploadDroppedItems(urls: urls, targetFolderId: folder.id)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.2)) {
                viewModel.folderDropTargetId = targeted ? folder.id : nil
            }
        }
    }

    // MARK: - Main Detail View (Liquid Design)
    private var mainDetailView: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // Top Section (Large Bold Title & Subtitle from Reference)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if !viewModel.isSidebarVisible {
                                Button {
                                    withAnimation(.spring(response: 0.25)) {
                                        viewModel.isSidebarVisible.toggle()
                                    }
                                } label: {
                                    Image(systemName: "sidebar.leading")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(textSidebar)
                                        .padding(5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color(red: 86/255.0, green: 82/255.0, blue: 81/255.0).opacity(0.45))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            // Confident Bold White Title with crisp specular finish
                            Text(viewModel.currentDisplayTitle)
                                .font(.system(size: 27, weight: .bold))
                                .foregroundColor(textPrimary)
                        }

                        // Explanatory Subtitle
                        Text(viewModel.currentDisplaySubtitle)
                            .font(.system(size: 13))
                            .foregroundColor(textSecondary)
                    }

                    Spacer()

                    // Liquid Toolbar Controls on Top Right
                    HStack(spacing: 8) {
                        // Liquid Search Pill
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(textSecondary)
                            TextField("Search files...", text: $viewModel.androidSearchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .frame(width: viewModel.androidSearchText.isEmpty ? 100 : 130)
                            if !viewModel.androidSearchText.isEmpty {
                                Button {
                                    viewModel.androidSearchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.045))
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                                )
                        )

                        // Liquid Glass View Switcher (Grid / List)
                        HStack(spacing: 2) {
                            Button {
                                viewModel.layoutMode = .grid
                            } label: {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(viewModel.layoutMode == .grid ? .white : textSecondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .background(
                                        Group {
                                            if viewModel.layoutMode == .grid {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color.white.opacity(0.12))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                                    )
                                                    .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.layoutMode = .list
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(viewModel.layoutMode == .list ? .white : textSecondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .background(
                                        Group {
                                            if viewModel.layoutMode == .list {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color.white.opacity(0.12))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                                    )
                                                    .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                        )

                        // Sort Menu Pill
                        Menu {
                            Picker("Sort By", selection: Binding(
                                get: { viewModel.sortCriteria },
                                set: { viewModel.sortCriteria = $0 }
                            )) {
                                ForEach(AppViewModel.SortCriteria.allCases) { c in
                                    Text(c.rawValue).tag(c)
                                }
                            }
                            Divider()
                            Button(viewModel.sortAscending ? "Ascending" : "Descending") {
                                viewModel.sortAscending.toggle()
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(textSecondary)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.045))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                        )
                                )
                        }
                        .menuStyle(.borderlessButton)

                        // New Folder Button Pill
                        Button {
                            viewModel.newFolderNameInput = ""
                            viewModel.showNewFolderSheet = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(textSecondary)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.045))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.deviceInfo == nil)
                        .help("New Folder")

                        // Refresh Button Pill
                        Button {
                            Task { await viewModel.refreshAndroidDirectory() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(textSecondary)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.045))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.deviceInfo == nil)
                        .help("Refresh")
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Breadcrumb path navigation bar (if inside subfolders)
                if viewModel.androidBreadcrumbs.count > 1 {
                    breadcrumbBar
                        .padding(.horizontal, 32)
                        .padding(.bottom, 14)
                }

                // Main Content: File Grid / List OR Disconnected State
                if viewModel.deviceInfo != nil {
                    fileListingView
                } else {
                    disconnectedView
                }
            }

            // Floating Liquid Transfer Island (Pill at bottom)
            if let progress = viewModel.currentProgress {
                floatingTransferIsland(progress: progress)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }

    // MARK: - Breadcrumb Bar (Liquid Glass Capsule)
    private var breadcrumbBar: some View {
        HStack(spacing: 5) {
            Button {
                Task { await viewModel.navigateUp() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textSecondary)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                ForEach(Array(viewModel.androidBreadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                    let isLast = (index == viewModel.androidBreadcrumbs.count - 1)
                    let isTarget = (viewModel.breadcrumbDropTargetId == crumb.id)

                    Button {
                        Task { await viewModel.navigateAndroidBreadcrumb(crumb) }
                    } label: {
                        Text(crumb.name)
                            .font(.system(size: 12, weight: isLast ? .medium : .regular))
                            .foregroundColor(isTarget ? blueAccent : (isLast ? .white : textSecondary))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isTarget ? blueAccent.opacity(0.20) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .dropDestination(for: URL.self) { urls, _ in
                        Task {
                            await viewModel.uploadDroppedItems(urls: urls, targetFolderId: crumb.id)
                        }
                        return true
                    } isTargeted: { targeted in
                        withAnimation(.spring(response: 0.2)) {
                            viewModel.breadcrumbDropTargetId = targeted ? crumb.id : nil
                        }
                    }

                    if !isLast {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(textSecondary.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - File Listing View (Grid & List in Liquid Dark Minimalist Style)
    private var fileListingView: some View {
        ScrollView {
            if viewModel.filteredAndSortedAndroidItems.isEmpty {
                // Liquid Empty State / Drop Zone
                VStack(spacing: 14) {
                    Spacer(minLength: 40)

                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                            )
                            .foregroundColor(viewModel.isDragOverWindow ? blueAccent : Color.white.opacity(0.12))
                            .frame(maxWidth: 420, minHeight: 180)

                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isDragOverWindow ? blueAccent.opacity(0.2) : Color.white.opacity(0.04))
                                    .frame(width: 52, height: 52)

                                Image(systemName: viewModel.isDragOverWindow ? "arrow.down.doc.fill" : "tray")
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundColor(viewModel.isDragOverWindow ? blueAccent : textSecondary)
                            }

                            Text(viewModel.isDragOverWindow ? "Release to Upload Files" : "This folder is empty")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)

                            Text("Drag any files or folders from Finder into this window to transfer.")
                                .font(.system(size: 12))
                                .foregroundColor(textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                        }
                        .padding(24)
                    }

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.layoutMode == .grid {
                // Large Clean Liquid Squircle Grid
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 116, maximum: 136), spacing: 18)],
                    spacing: 18
                ) {
                    ForEach(viewModel.filteredAndSortedAndroidItems) { item in
                        gridFileCard(item: item)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .padding(.bottom, 60) // Extra padding so floating island never covers files
            } else {
                // Clean Liquid Minimalist Rows
                LazyVStack(spacing: 3) {
                    ForEach(viewModel.filteredAndSortedAndroidItems) { item in
                        listFileRow(item: item)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Grid File Card (Liquid Squircle Design with Thumbnail Support)
    private func gridFileCard(item: MTPItem) -> some View {
        let isSelected = viewModel.androidSelection.contains(item.id)
        let isTarget = (viewModel.folderDropTargetId == item.id)
        let isHovered = (viewModel.hoveredItemId == item.id)
        let targetGreen = Color(red: 0.22, green: 0.82, blue: 0.44)
        let vm = viewModel

        let card = VStack(spacing: 7) {
            ZStack {
                if item.isFolder {
                    ModernFolderIconView(isTarget: isTarget, size: 48)
                } else if item.isImage {
                    if let thumb = viewModel.thumbnailCache[item.id] {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.35), radius: 3, y: 2)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 56, height: 56)

                            Image(systemName: "photo.fill")
                                .font(.system(size: 32, weight: .regular))
                                .foregroundColor(Color(red: item.iconTint.r, green: item.iconTint.g, blue: item.iconTint.b))
                        }
                        .task {
                            await viewModel.requestThumbnail(for: item)
                        }
                    }
                } else {
                    Image(systemName: item.systemImageName)
                        .font(.system(size: 44, weight: .regular))
                        .foregroundColor(
                            Color(red: item.iconTint.r, green: item.iconTint.g, blue: item.iconTint.b)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                }
            }
            .frame(width: 58, height: 56)

            Text(item.name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : textSidebar)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 106)

            if isTarget {
                Text("Drop inside")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(targetGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(targetGreen.opacity(0.22))
                    )
            } else {
                Text(item.formattedSize)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(textSecondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 118, height: 122)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isTarget ? targetGreen.opacity(0.20) :
                    (isSelected ? itemSelectedBg : (isHovered ? itemHoverBg : Color.white.opacity(0.015)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isTarget ? targetGreen :
                            (isSelected ? Color.white.opacity(0.20) : (isHovered ? Color.white.opacity(0.07) : Color.clear)),
                            lineWidth: isTarget ? 1.5 : 1
                        )
                )
        )
        .scaleEffect(isTarget ? 1.04 : 1.0)
        .animation(.spring(response: 0.22), value: isTarget)
        .contentShape(Rectangle())
        .onHover { hovering in
            viewModel.hoveredItemId = hovering ? item.id : nil
        }
        .onTapGesture(count: 2) {
            if item.isFolder {
                Task { await viewModel.openAndroidFolder(item) }
            } else {
                Task { await viewModel.previewSelectedItem() }
            }
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                viewModel.toggleSelection(for: item.id)
            } else if flags.contains(.shift) {
                viewModel.selectRange(to: item.id)
            } else {
                viewModel.selectSingle(item.id)
            }
        }
        // Drag directly to Finder
        .onDrag {
            let provider = NSItemProvider()
            provider.suggestedName = item.name
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.data.identifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                vm.startDragDownload(item: item, completion: completion)
            }
            return provider
        }
        .contextMenu {
            contextMenuItems(for: item)
        }

        return Group {
            if item.isFolder {
                card.dropDestination(for: URL.self) { urls, _ in
                    Task {
                        await vm.uploadDroppedItems(urls: urls, targetFolderId: item.id)
                    }
                    return true
                } isTargeted: { targeted in
                    withAnimation(.spring(response: 0.2)) {
                        vm.folderDropTargetId = targeted ? item.id : nil
                    }
                }
            } else {
                card
            }
        }
    }

    // MARK: - List File Row (Liquid Row Design with Thumbnail Support)
    private func listFileRow(item: MTPItem) -> some View {
        let isSelected = viewModel.androidSelection.contains(item.id)
        let isTarget = (viewModel.folderDropTargetId == item.id)
        let isHovered = (viewModel.hoveredItemId == item.id)
        let targetGreen = Color(red: 0.22, green: 0.82, blue: 0.44)
        let vm = viewModel

        let row = HStack(spacing: 10) {
            if item.isFolder {
                ModernFolderIconView(isTarget: isTarget, size: 18)
                    .frame(width: 22)
            } else if item.isImage {
                if let thumb = viewModel.thumbnailCache[item.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                } else {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: item.iconTint.r, green: item.iconTint.g, blue: item.iconTint.b))
                        .frame(width: 22)
                        .task {
                            await viewModel.requestThumbnail(for: item)
                        }
                }
            } else {
                Image(systemName: item.systemImageName)
                    .font(.system(size: 17))
                    .foregroundColor(Color(red: item.iconTint.r, green: item.iconTint.g, blue: item.iconTint.b))
                    .frame(width: 22)
            }

            Text(item.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : textSidebar)
                .lineLimit(1)

            Spacer()

            if isTarget {
                Text("Drop inside")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(targetGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(targetGreen.opacity(0.2))
                    )
            } else {
                Text(item.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(textSecondary)
                    .frame(width: 130, alignment: .trailing)

                Text(item.formattedSize)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(textSecondary)
                    .frame(width: 75, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isTarget ? targetGreen.opacity(0.18) :
                    (isSelected ? itemSelectedBg : (isHovered ? itemHoverBg : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isTarget ? targetGreen :
                            (isSelected ? Color.white.opacity(0.08) : Color.clear),
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            viewModel.hoveredItemId = hovering ? item.id : nil
        }
        .onTapGesture(count: 2) {
            if item.isFolder {
                Task { await viewModel.openAndroidFolder(item) }
            } else {
                Task { await viewModel.previewSelectedItem() }
            }
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                viewModel.toggleSelection(for: item.id)
            } else if flags.contains(.shift) {
                viewModel.selectRange(to: item.id)
            } else {
                viewModel.selectSingle(item.id)
            }
        }
        .onDrag {
            let provider = NSItemProvider()
            provider.suggestedName = item.name
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.data.identifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                vm.startDragDownload(item: item, completion: completion)
            }
            return provider
        }
        .contextMenu {
            contextMenuItems(for: item)
        }

        return Group {
            if item.isFolder {
                row.dropDestination(for: URL.self) { urls, _ in
                    Task {
                        await vm.uploadDroppedItems(urls: urls, targetFolderId: item.id)
                    }
                    return true
                } isTargeted: { targeted in
                    withAnimation(.spring(response: 0.2)) {
                        vm.folderDropTargetId = targeted ? item.id : nil
                    }
                }
            } else {
                row
            }
        }
    }

    // MARK: - Context Menu
    @ViewBuilder
    private func contextMenuItems(for item: MTPItem) -> some View {
        if !item.isFolder {
            Button("Quick Look (Space)") {
                Task { await viewModel.previewSelectedItem() }
            }
            Button("Download to Downloads") {
                Task { await viewModel.downloadSelectedAndroidItems() }
            }
            Button("Download to...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Save"
                if panel.runModal() == .OK, let targetURL = panel.url {
                    Task { await viewModel.downloadSelectedAndroidItems(to: targetURL) }
                }
            }
            Divider()
        }
        Button("Rename...") {
            viewModel.renameItemTarget = item
            viewModel.renameTargetName = item.name
            viewModel.showRenameSheet = true
        }
        Button("Delete", role: .destructive) {
            Task { await viewModel.deleteSelectedAndroidItems() }
        }
    }

    // MARK: - Disconnected View (Liquid Glass Hub)
    private var disconnectedView: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                // Soft liquid radial glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [blueAccent.opacity(0.18), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "cable.connector.slash")
                    .font(.system(size: 42, weight: .light))
                    .foregroundColor(textSecondary)
            }

            Text("Connect Android via USB")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(textPrimary)

            Text("Unlock your phone and select 'File Transfer (MTP)' in USB Settings.")
                .font(.system(size: 13))
                .foregroundColor(textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            if !viewModel.conflictingProcesses.isEmpty {
                VStack(spacing: 8) {
                    Text("USB port claimed by: \(viewModel.conflictingProcesses.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button("Release Port & Connect") {
                        Task { await viewModel.killConflictsAndReconnect() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
                        )
                )
            }

            Button {
                Task { await viewModel.connectDevice() }
            } label: {
                if viewModel.isConnecting {
                    ProgressView().controlSize(.small)
                        .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text("Connect Device")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
            }
            .buttonStyle(.plain)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [blueAccent, Color(red: 0.22, green: 0.52, blue: 0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: blueAccent.opacity(0.3), radius: 6, y: 2)
            )
            .foregroundColor(.white)
            .disabled(viewModel.isConnecting)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Floating Liquid Transfer Island
    private func floatingTransferIsland(progress: TransferProgress) -> some View {
        let isDone = progress.isCompleted
        let successGreen = Color(red: 0.22, green: 0.82, blue: 0.44) // #38D170 vibrant emerald green
        let accent = isDone ? successGreen : blueAccent

        return HStack(spacing: 12) {
            // State / Direction icon
            Image(systemName: isDone ? "checkmark.circle.fill" : (progress.direction == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill"))
                .foregroundColor(accent)
                .font(.system(size: isDone ? 16 : 15, weight: .semibold))

            // File Name & Status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(isDone ? "Transfer Complete" : (progress.direction == .upload ? "Copying to Phone" : "Copying to Mac"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(textSecondary)

                    Text(isDone ? "100%" : "\(Int(progress.fractionCompleted * 100))%")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(accent)
                }

                Text(progress.fileName)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 160, alignment: .leading)

            // Dynamic linear progress bar
            ProgressView(value: isDone ? 1.0 : progress.fractionCompleted)
                .progressViewStyle(.linear)
                .tint(accent)
                .frame(width: 130)
                .animation(.linear(duration: 0.1), value: progress.fractionCompleted)

            // Byte counts
            Text(isDone
                ? ByteCountFormatter.string(fromByteCount: Int64(progress.totalBytes), countStyle: .file)
                : "\(ByteCountFormatter.string(fromByteCount: Int64(progress.bytesTransferred), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(progress.totalBytes), countStyle: .file))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(textSecondary)

            // Trailing Action: Cancel (if in progress) OR Dismiss (if complete)
            if isDone {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        viewModel.currentProgress = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(textSecondary)
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            } else {
                Button {
                    viewModel.cancelTransfer()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(blueAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.white.opacity(0.08))
                                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color(red: 36/255.0, green: 32/255.0, blue: 31/255.0).opacity(0.96))
                .overlay(
                    Capsule().stroke(isDone ? successGreen.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 16, y: 8)
        )
    }

    // MARK: - Sheets
    private var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Folder")
                .font(.headline)
            TextField("Folder Name", text: $viewModel.newFolderNameInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.showNewFolderSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let name = viewModel.newFolderNameInput
                    viewModel.showNewFolderSheet = false
                    Task { await viewModel.createAndroidFolder(name: name) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newFolderNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
        .preferredColorScheme(.dark)
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename")
                .font(.headline)
            TextField("Name", text: $viewModel.renameTargetName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.showRenameSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    if let target = viewModel.renameItemTarget {
                        let name = viewModel.renameTargetName
                        viewModel.showRenameSheet = false
                        Task { await viewModel.renameAndroidItem(target, to: name) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.renameTargetName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
        .preferredColorScheme(.dark)
    }

    private var deviceInfoSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Device Information")
                .font(.headline)

            if let device = viewModel.deviceInfo {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(label: "Device", value: device.friendlyName)
                    infoRow(label: "Manufacturer", value: device.manufacturer)
                    infoRow(label: "Model", value: device.modelName)
                    infoRow(label: "Battery", value: "\(device.batteryLevelPercent)% \(device.isCharging ? "• Charging" : "")")
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
            } else {
                Text("No device connected.")
                    .foregroundColor(textSecondary)
            }

            HStack {
                if viewModel.deviceInfo != nil {
                    Button(role: .destructive) {
                        viewModel.showDeviceSheet = false
                        Task { await viewModel.disconnectDevice() }
                    } label: {
                        Text("Disconnect")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Done") {
                    viewModel.showDeviceSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
        .preferredColorScheme(.dark)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(textSecondary)
                .font(.system(size: 12))
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .font(.system(size: 12, weight: .medium))
        }
    }

    // MARK: - Conflict Resolution Sheet
    private func conflictResolutionSheet(conflict: TransferConflict) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(goldAccent)

                VStack(alignment: .leading, spacing: 5) {
                    Text("File Already Exists")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(textPrimary)

                    Text("An item named “\(conflict.fileName)” already exists at the destination (\(conflict.destinationPath)).")
                        .font(.system(size: 12))
                        .foregroundColor(textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Size comparison box
            VStack(spacing: 6) {
                HStack {
                    Text("Incoming file:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textSecondary)
                    Spacer()
                    Text(conflict.newFileSize != nil ? ByteCountFormatter.string(fromByteCount: Int64(conflict.newFileSize!), countStyle: .file) : "Unknown")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.white)
                }
                HStack {
                    Text("Existing file:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textSecondary)
                    Spacer()
                    Text(conflict.existingFileSize != nil ? ByteCountFormatter.string(fromByteCount: Int64(conflict.existingFileSize!), countStyle: .file) : "Unknown")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(textSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )

            // Apply to all toggle
            Toggle("Apply to all remaining conflicts", isOn: $viewModel.applyConflictToAll)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundColor(textSidebar)

            // Actions
            HStack(spacing: 10) {
                Button("Skip") {
                    viewModel.resolveConflict(action: .skip)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Keep Both") {
                    viewModel.resolveConflict(action: .keepBoth)
                }

                Button("Replace") {
                    viewModel.resolveConflict(action: .replace)
                }
                .buttonStyle(.borderedProminent)
                .tint(blueAccent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
        .preferredColorScheme(.dark)
    }
}
