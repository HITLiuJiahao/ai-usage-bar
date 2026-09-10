import AppKit
import SwiftUI

struct DesktopPetSettingsSection: View {
    @ObservedObject private var pet = DesktopPetStore.shared
    @State private var idleMessage = ""
    @State private var workingMessage = ""
    @State private var waitingMessage = ""
    @State private var completedMessage = ""
    @State private var clearConfirmation = false
    @State private var shortcutConflict: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(
                PetUI.text("显示桌面宠物", "Show desktop pet"),
                isOn: boolBinding(get: { pet.preferences.isEnabled }, set: pet.setEnabled)
            )

            HStack(spacing: 10) {
                Button {
                    DesktopPetWindowController.shared.showPet()
                } label: {
                    Label(PetUI.text("立即显示", "Show Now"), systemImage: "sparkles")
                }
                Button {
                    DesktopPetWindowController.shared.showHUDFromSettings()
                } label: {
                    Label(PetUI.text("查看宠物面板", "Open Pet HUD"), systemImage: "rectangle.inset.filled")
                }
                Button {
                    pet.resetPetPosition()
                } label: {
                    Label(PetUI.text("重置位置", "Reset Position"), systemImage: "arrow.counterclockwise")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(PetUI.text("宠物快捷键", "Pet Shortcuts"))
                    .font(.headline)
                Text(PetUI.text(
                    "可在任何应用中使用。点击右侧按钮后按下新的组合键，按 Esc 取消录入。",
                    "These work in any app. Click a button, then press a new key combination; press Esc to cancel."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(PetUI.text("开启宠物", "Show desktop pet"))
                    Spacer()
                    PetShortcutRecorder(shortcut: pet.showPetShortcut) { shortcut in
                        if !pet.setShowPetShortcut(shortcut) {
                            shortcutConflict = PetUI.text(
                                "开启和关闭快捷键不能相同。",
                                "The show and hide shortcuts must be different."
                            )
                        } else {
                            shortcutConflict = nil
                        }
                    }
                    .frame(width: 132, height: 28)
                }
                HStack {
                    Text(PetUI.text("关闭宠物", "Hide desktop pet"))
                    Spacer()
                    PetShortcutRecorder(shortcut: pet.hidePetShortcut) { shortcut in
                        if !pet.setHidePetShortcut(shortcut) {
                            shortcutConflict = PetUI.text(
                                "开启和关闭快捷键不能相同。",
                                "The show and hide shortcuts must be different."
                            )
                        } else {
                            shortcutConflict = nil
                        }
                    }
                    .frame(width: 132, height: 28)
                }
                HStack {
                    if let shortcutConflict {
                        Text(shortcutConflict)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button(PetUI.text("恢复默认", "Restore Defaults")) {
                        pet.resetPetShortcuts()
                        shortcutConflict = nil
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(PetUI.text("大小", "Size"))
                    Spacer()
                    Text("\(Int(pet.preferences.petSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: doubleBinding(get: { pet.preferences.petSize }, set: pet.setPetSize),
                    in: 72...180,
                    step: 1
                )
                HStack {
                    Text(PetUI.text("不透明度", "Opacity"))
                    Spacer()
                    Text("\(Int((pet.preferences.opacity * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: doubleBinding(get: { pet.preferences.opacity }, set: pet.setOpacity),
                    in: 0.35...1,
                    step: 0.05
                )
            }

            Divider()

            Toggle(
                PetUI.text("显示状态气泡", "Show status bubbles"),
                isOn: boolBinding(get: { pet.preferences.showMessages }, set: pet.setShowMessages)
            )
            Toggle(
                PetUI.text("任务完成或等待时通知我", "Notify when an agent finishes or waits"),
                isOn: boolBinding(get: { pet.preferences.notificationsEnabled }, set: pet.setNotificationsEnabled)
            )
            Toggle(
                PetUI.text("通知播放声音", "Play notification sounds"),
                isOn: boolBinding(get: { pet.preferences.soundEnabled }, set: pet.setSoundEnabled)
            )
            .disabled(!pet.preferences.notificationsEnabled)
            Toggle(
                PetUI.text("久坐休息提醒", "Break reminders"),
                isOn: boolBinding(get: { pet.preferences.breakRemindersEnabled }, set: pet.setBreakRemindersEnabled)
            )
            if pet.preferences.breakRemindersEnabled {
                Stepper(
                    "\(PetUI.text("提醒间隔", "Reminder interval")) · \(pet.preferences.breakReminderMinutes) \(PetUI.text("分钟", "min"))",
                    value: intBinding(get: { pet.preferences.breakReminderMinutes }, set: pet.setBreakReminderMinutes),
                    in: 15...180,
                    step: 5
                )
            }

            Divider()

            Picker(
                PetUI.text("当前宠物", "Current pet"),
                selection: stringBinding(get: { pet.preferences.selectedPackID }, set: pet.setSelectedPack)
            ) {
                ForEach(pet.packs) { pack in
                    Text(pack.name).tag(pack.id)
                }
            }
            HStack {
                Button {
                    pet.importPack()
                } label: {
                    Label(PetUI.text("导入宠物包…", "Import Pet Pack…"), systemImage: "square.and.arrow.down")
                }
                Text(PetUI.text("支持 pet.json + 透明 PNG 精灵图", "Supports pet.json + transparent PNG sprites"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                PetUI.text("按项目使用专属宠物", "Use project-specific pets"),
                isOn: boolBinding(get: { pet.preferences.splitByProject }, set: pet.setSplitByProject)
            )
            if pet.preferences.splitByProject {
                VStack(alignment: .leading, spacing: 6) {
                    if pet.projectMappings.isEmpty {
                        Text(PetUI.text("尚未绑定项目；收到带项目路径的 Hook 事件后，将使用匹配的宠物。", "No projects are bound yet. Matching hook events use the assigned pet."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pet.projectMappings) { mapping in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.cyan)
                                Text(URL(fileURLWithPath: mapping.projectPath).lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Text(pet.packs.first(where: { $0.id == mapping.packID })?.name ?? "—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    pet.removeProjectMapping(mapping)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button {
                        pet.addProjectMapping()
                    } label: {
                        Label(PetUI.text("绑定项目文件夹…", "Bind Project Folder…"), systemImage: "folder.badge.plus")
                    }
                }
                .padding(.leading, 2)
            }

            Divider()

            DisclosureGroup(PetUI.text("自定义气泡文案", "Custom bubble messages")) {
                VStack(spacing: 7) {
                    TextField(PetUI.text("空闲时", "Idle"), text: $idleMessage)
                    TextField(PetUI.text("工作时", "Working"), text: $workingMessage)
                    TextField(PetUI.text("等待或受阻时", "Waiting or blocked"), text: $waitingMessage)
                    TextField(PetUI.text("完成时", "Completed"), text: $completedMessage)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 6)
            }

            DisclosureGroup(PetUI.text("Agent Hook 桥接", "Agent Hook Bridge")) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(PetUI.text("本机 Unix Socket 只接收状态和可选 Token 数，不读取提示词或账号凭据。", "The local Unix socket accepts state and optional tokens only; it never reads prompts or credentials."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(PetEventCommand.exampleCommand())
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(PetEventCommand.exampleCommand(), forType: .string)
                    } label: {
                        Label(PetUI.text("复制示例命令", "Copy Example Command"), systemImage: "doc.on.doc")
                    }
                }
                .padding(.top, 6)
            }

            DisclosureGroup("\(PetUI.text("成就", "Achievements")) · \(pet.achievements.count)/\(DesktopPetAchievement.allCases.count)") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(DesktopPetAchievement.allCases) { achievement in
                        Label(PetUI.achievement(achievement), systemImage: pet.achievements.contains(achievement) ? "checkmark.seal.fill" : "lock.fill")
                            .font(.caption)
                            .foregroundStyle(pet.achievements.contains(achievement) ? Color.yellow : Color.secondary)
                    }
                }
                .padding(.top, 7)
            }

            DisclosureGroup("\(PetUI.text("会话历史", "Session History")) · \(pet.sessionArchive.count)") {
                if pet.sessionArchive.isEmpty {
                    Text(PetUI.text("尚未收到已完成的 Agent Hook 会话。", "No completed agent-hook sessions yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(pet.sessionArchive.prefix(12))) { entry in
                            HStack(spacing: 7) {
                                if let provider = entry.provider {
                                    ProviderLogo(
                                        provider: provider,
                                        size: 14,
                                        fallbackColor: ProviderPalette.color(for: provider)
                                    )
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .frame(width: 14)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.message ?? URL(fileURLWithPath: entry.projectPath ?? "").lastPathComponent)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    if let model = entry.model, !model.isEmpty {
                                        Text(model)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(entry.endedAt, style: .relative)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }

            Button(role: .destructive) {
                clearConfirmation = true
            } label: {
                Label(PetUI.text("清除宠物成长记录", "Clear Pet Progress"), systemImage: "trash")
            }
            .confirmationDialog(
                PetUI.text("清除所有本地宠物成长、历史和成就？", "Clear all local pet progress, history, and achievements?"),
                isPresented: $clearConfirmation,
                titleVisibility: .visible
            ) {
                Button(PetUI.text("清除", "Clear"), role: .destructive) {
                    pet.clearHistory()
                }
            }
        }
        .onAppear(perform: loadMessages)
        .onChange(of: idleMessage) { _ in saveMessages() }
        .onChange(of: workingMessage) { _ in saveMessages() }
        .onChange(of: waitingMessage) { _ in saveMessages() }
        .onChange(of: completedMessage) { _ in saveMessages() }
    }

    private func loadMessages() {
        idleMessage = pet.preferences.idleMessage
        workingMessage = pet.preferences.workingMessage
        waitingMessage = pet.preferences.waitingMessage
        completedMessage = pet.preferences.completedMessage
    }

    private func saveMessages() {
        pet.setCustomMessages(
            idle: idleMessage,
            working: workingMessage,
            waiting: waitingMessage,
            completed: completedMessage
        )
    }

    private func boolBinding(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: set)
    }

    private func doubleBinding(get: @escaping () -> Double, set: @escaping (Double) -> Void) -> Binding<Double> {
        Binding(get: get, set: set)
    }

    private func intBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(get: get, set: set)
    }

    private func stringBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: get, set: set)
    }
}
