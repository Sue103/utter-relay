import Foundation

// MARK: - リレーの保存領域(voicequick_clipboard.pyのClipboardStoreと同じ役割。SQLiteの代わりにJSONファイル)
final class ClipboardStore {
    private let queue = DispatchQueue(label: "voicequickrelay.store")
    private var items: [ClipboardItem] = []
    private var nextRevision = 1
    private let fileURL: URL
    private let maxItems = 500

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    @discardableResult
    func put(_ incoming: ClipboardItem) -> ClipboardItem {
        queue.sync {
            if let existing = items.first(where: { $0.id == incoming.id }) {
                return existing
            }
            var item = incoming
            item.revision = nextRevision
            nextRevision += 1
            items.append(item)
            if items.count > maxItems {
                items.removeFirst(items.count - maxItems)
            }
            persist()
            return item
        }
    }

    func latest(excludingDevice: String, platform: String, afterRevision: Int) -> ClipboardItem? {
        queue.sync {
            let candidates = items
                .filter { $0.originDevice != excludingDevice && ($0.revision ?? 0) > afterRevision }
                .sorted { ($0.revision ?? 0) > ($1.revision ?? 0) }
            for item in candidates {
                if item.targets.contains("all") || item.targets.contains(platform) {
                    return item
                }
            }
            return nil
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
        nextRevision = (items.compactMap(\.revision).max() ?? 0) + 1
    }
}
