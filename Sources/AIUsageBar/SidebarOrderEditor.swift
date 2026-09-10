import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarOrderEditor: View {
    @ObservedObject private var providerOrder = ProviderOrderStore.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.text(.dragToReorder, language: languageSettings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        providerOrder.reset()
                    }
                } label: {
                    Text(L10n.text(.restoreDefault, language: languageSettings.language))
                }
                .buttonStyle(.link)
                .disabled(providerOrder.isDefault)
            }

            VStack(spacing: 0) {
                ForEach(providerOrder.order) { provider in
                    SidebarOrderRow(
                        provider: provider,
                        isFirst: providerOrder.order.first?.rawValue == provider.rawValue,
                        isLast: providerOrder.order.last?.rawValue == provider.rawValue,
                        moveUp: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                providerOrder.moveUp(provider)
                            }
                        },
                        moveDown: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                providerOrder.moveDown(provider)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onDrag {
                        providerOrder.beginDragging(provider)
                        return NSItemProvider(object: NSString(string: provider.rawValue))
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: SidebarOrderDropDelegate(
                            target: provider,
                            store: providerOrder
                        )
                    )

                    if provider.rawValue != providerOrder.order.last?.rawValue {
                        Divider()
                            .padding(.leading, 38)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct SidebarOrderRow: View {
    let provider: ProviderID
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            ProviderLogo(
                provider: provider,
                size: 25,
                fallbackColor: ProviderPalette.color(for: provider)
            )

            Text(L10n.providerName(provider, language: languageSettings.language))
                .font(.system(size: 13, weight: .medium, design: .rounded))

            Spacer(minLength: 8)

            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help(L10n.text(.moveUp, language: languageSettings.language))

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help(L10n.text(.moveDown, language: languageSettings.language))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct SidebarOrderDropDelegate: DropDelegate {
    let target: ProviderID
    let store: ProviderOrderStore

    func dropEntered(info: DropInfo) {
        guard let draggedProvider = store.draggedProvider,
              draggedProvider != target
        else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            store.move(draggedProvider, before: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        store.endDragging()
        return true
    }
}
