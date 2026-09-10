import Combine
import Foundation

/// Stores the user's preferred order for the provider rail and keeps the
/// ordering available to every surface that presents provider snapshots.
final class ProviderOrderStore: ObservableObject {
    static let shared = ProviderOrderStore()

    private static let defaultsKey = "aiUsageBar.sidebarProviderOrder"

    @Published private(set) var order: [ProviderID]
    @Published private(set) var draggedProvider: ProviderID?

    private init() {
        order = Self.loadOrder()
    }

    func beginDragging(_ provider: ProviderID) {
        draggedProvider = provider
    }

    func endDragging() {
        draggedProvider = nil
    }

    func orderedSnapshots(_ snapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        let snapshotsByProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        var ordered = order.compactMap { snapshotsByProvider[$0] }
        let orderedProviders = Set(ordered.map(\.provider))
        ordered.append(contentsOf: snapshots.filter { !orderedProviders.contains($0.provider) })
        return ordered
    }

    func move(_ provider: ProviderID, before target: ProviderID) {
        guard provider != target,
              let sourceIndex = order.firstIndex(of: provider),
              let targetIndex = order.firstIndex(of: target)
        else { return }

        var updated = order
        updated.remove(at: sourceIndex)
        let insertionIndex = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
        updated.insert(provider, at: insertionIndex)
        save(updated)
    }

    func moveUp(_ provider: ProviderID) {
        guard let index = order.firstIndex(of: provider), index > 0 else { return }
        var updated = order
        updated.swapAt(index, index - 1)
        save(updated)
    }

    func moveDown(_ provider: ProviderID) {
        guard let index = order.firstIndex(of: provider), index + 1 < order.count else { return }
        var updated = order
        updated.swapAt(index, index + 1)
        save(updated)
    }

    func reset() {
        save(ProviderID.trackedCases)
    }

    var isDefault: Bool {
        order == ProviderID.trackedCases
    }

    private func save(_ preferredOrder: [ProviderID]) {
        let normalizedOrder = Self.normalized(preferredOrder)
        guard normalizedOrder != order else { return }

        order = normalizedOrder
        UserDefaults.standard.set(
            normalizedOrder.map(\.rawValue),
            forKey: Self.defaultsKey
        )
    }

    private static func loadOrder() -> [ProviderID] {
        let savedRawValues = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        let savedProviders = savedRawValues.compactMap(ProviderID.init(rawValue:))
        return normalized(savedProviders)
    }

    private static func normalized(_ preferredOrder: [ProviderID]) -> [ProviderID] {
        var seen = Set<ProviderID>()
        var result = preferredOrder.filter { provider in
            ProviderID.trackedCases.contains(provider) && seen.insert(provider).inserted
        }
        result.append(contentsOf: ProviderID.trackedCases.filter { seen.insert($0).inserted })
        return result
    }
}
