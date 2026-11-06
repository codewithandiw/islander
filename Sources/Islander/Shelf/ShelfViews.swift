import SwiftUI

struct ShelfTabView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var island: IslandModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Shelf")
                    .font(.system(size: 14, weight: .semibold))
                Text(shelf.items.isEmpty ? "Max 10 MB per file" : "\(shelf.items.count) file\(shelf.items.count == 1 ? "" : "s") · \(ShelfStore.format(shelf.totalSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                if let message = shelf.message {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .transition(.blurReplace)
                }
                if !shelf.items.isEmpty {
                    CleanButton { shelf.clean() }
                }
            }
            .animation(.smooth(duration: 0.3), value: shelf.message)

            if shelf.items.isEmpty {
                DropZone(isTargeted: island.isDropTargeted)
            } else {
                if isSnapshot {
                    itemRow
                } else {
                    ScrollView(.horizontal, showsIndicators: false) { itemRow }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: shelf.items)
    }

    private var itemRow: some View {
        HStack(spacing: 12) {
            ForEach(shelf.items) { item in
                ShelfItemView(item: item, thumbnail: shelf.thumbnails[item.id])
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.vertical, 2)
        .padding(.trailing, 6)
    }
}

/// Empty-state target with a dashed outline that lights up while a file is dragged over.
private struct DropZone: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isTargeted ? Color.cyan : Color.white.opacity(0.25),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isTargeted ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolEffect(.bounce, value: isTargeted)
                    Text(isTargeted ? "Release to add" : "Drop screenshots or files here")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(isTargeted ? .cyan : .white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.25), value: isTargeted)
    }
}

private struct ShelfItemView: View {
    @EnvironmentObject private var shelf: ShelfStore

    let item: ShelfItem
    let thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                        .transition(.opacity)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("Remove from shelf")
            }

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 76)
            Text(ShelfStore.format(item.size))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
        }
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Copy") { shelf.copyToPasteboard(item) }
            Button("Show in Finder") { shelf.revealInFinder(item) }
            Divider()
            Button("Remove", role: .destructive) { shelf.remove(item) }
        }
        .help("\(item.name) — drag out to use, double-click to open")
    }
}

/// Two-step button: the first click asks, the second click deletes.
private struct CleanButton: View {
    let action: () -> Void
    @State private var confirming = false

    var body: some View {
        Button {
            if confirming {
                confirming = false
                action()
            } else {
                confirming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirming = false }
            }
        } label: {
            Label(confirming ? "Delete all?" : "Clean", systemImage: "trash")
                .contentTransition(.interpolate)
        }
        .buttonStyle(IslandButtonStyle(tint: confirming ? .red : nil))
        .animation(.smooth(duration: 0.2), value: confirming)
    }
}
