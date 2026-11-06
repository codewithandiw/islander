import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let addedAt: Date
}

/// Temporary file shelf. Dropped files are copied into a private temp folder; the
/// originals are never touched. The shelf is emptied on quit.
@MainActor
final class ShelfStore: ObservableObject {
    // Decimal megabytes, matching how Finder and ByteCountFormatter show sizes.
    static let maxFileSize: Int64 = 10_000_000
    static let maxTotalSize: Int64 = 100_000_000

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    /// Short feedback such as "photo.heic is 23 MB. The limit is 10 MB per file."
    @Published private(set) var message: String?

    private let directory: URL
    private var messageWork: DispatchWorkItem?
    /// Size of copies still in progress, so parallel drops cannot exceed the total limit.
    private var reservedSize: Int64 = 0

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    init(fileManager: FileManager = .default) {
        directory = fileManager.temporaryDirectory.appendingPathComponent("IslanderShelf", isDirectory: true)
        // Remove leftovers from a previous run that did not quit cleanly.
        try? fileManager.removeItem(at: directory)
    }

    // MARK: - Adding

    /// Accepts files, images (for example from a browser) and plain text.
    func add(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { self?.addFile(url) }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    guard let image = object as? NSImage,
                          let tiff = image.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                    else { return }
                    DispatchQueue.main.async { self?.addData(png, name: "Image \(Self.stamp()).png") }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                    guard let text = object as? String, let data = text.data(using: .utf8) else { return }
                    DispatchQueue.main.async { self?.addData(data, name: "Text \(Self.stamp()).txt") }
                }
            }
        }
    }

    func addFile(_ source: URL) {
        let values = try? source.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isRegularFileKey])
        let name = source.lastPathComponent
        if values?.isDirectory == true {
            show("\(name) is a folder. Only files can go on the shelf.")
            return
        }
        guard let size = values?.fileSize.map(Int64.init), values?.isRegularFile == true else {
            show("Could not read \(name).")
            return
        }
        guard accepts(size: size, name: name) else { return }

        let id = UUID()
        let destination = folder(for: id).appendingPathComponent(name)
        reservedSize += size
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
            }
            await self?.finishAdding(id: id, url: destination, size: size, result: result)
        }
    }

    private func addData(_ data: Data, name: String) {
        let size = Int64(data.count)
        guard accepts(size: size, name: name) else { return }
        let id = UUID()
        let destination = folder(for: id).appendingPathComponent(name)
        reservedSize += size
        let result = Result {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination)
        }
        finishAdding(id: id, url: destination, size: size, result: result)
    }

    private func accepts(size: Int64, name: String) -> Bool {
        if size > Self.maxFileSize {
            show("\(name) is \(Self.format(size)). The limit is 10 MB per file.")
            return false
        }
        if totalSize + reservedSize + size > Self.maxTotalSize {
            show("The shelf is full (100 MB). Clean it to add more.")
            return false
        }
        return true
    }

    private func finishAdding(id: UUID, url: URL, size: Int64, result: Result<Void, Error>) {
        reservedSize -= size
        switch result {
        case .success:
            let item = ShelfItem(id: id, url: url, name: url.lastPathComponent, size: size, addedAt: .now)
            items.insert(item, at: 0)
            loadThumbnail(for: item)
        case .failure(let error):
            try? FileManager.default.removeItem(at: folder(for: id))
            show("Could not add \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Using and removing

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Puts the file on the clipboard, so it can be pasted into chat apps or Finder.
    func copyToPasteboard(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
        show("Copied \(item.name)")
    }

    func remove(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: folder(for: item.id))
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
    }

    /// Deletes every shelf copy. Originals are not affected.
    func clean() {
        try? FileManager.default.removeItem(at: directory)
        items.removeAll()
        thumbnails.removeAll()
    }

    // MARK: - Helpers

    /// Each file gets its own folder, so two files with the same name never collide.
    private func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func loadThumbnail(for item: ShelfItem) {
        thumbnails[item.id] = NSWorkspace.shared.icon(forFile: item.url.path)
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 128, height: 128),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                guard self?.items.contains(where: { $0.id == item.id }) == true else { return }
                self?.thumbnails[item.id] = image
            }
        }
    }

    private func show(_ text: String) {
        messageWork?.cancel()
        message = text
        let work = DispatchWorkItem { [weak self] in self?.message = nil }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private nonisolated static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: .now)
    }
}
