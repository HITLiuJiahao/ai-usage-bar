import AppKit
import SwiftUI

enum PetUI {
    static func text(_ zh: String, _ en: String, _ ja: String? = nil, _ ko: String? = nil) -> String {
        switch AppLanguageSettings.shared.language {
        case .simplifiedChinese: return zh
        case .english: return en
        case .japanese: return ja ?? en
        case .korean: return ko ?? en
        }
    }

    static func codexAction(_ action: CodexPetTaskAction) -> String {
        switch action {
        case .starting:
            return text("正在启动任务", "Starting task", "タスクを開始中", "작업 시작 중")
        case .thinking:
            return text("正在思考", "Thinking", "思考中", "생각 중")
        case .runningCommand:
            return text("正在运行命令", "Running a command", "コマンドを実行中", "명령 실행 중")
        case .editingFiles:
            return text("正在修改文件", "Editing files", "ファイルを編集中", "파일 수정 중")
        case .readingFiles:
            return text("正在读取文件", "Reading files", "ファイルを読み取り中", "파일 읽는 중")
        case .searchingWeb:
            return text("正在搜索网页", "Searching the web", "ウェブを検索中", "웹 검색 중")
        case .callingTool:
            return text("正在调用工具", "Calling a tool", "ツールを呼び出し中", "도구 호출 중")
        case .waitingForInput:
            return text("正在等待输入", "Waiting for input", "入力を待機中", "입력 대기 중")
        }
    }

    static func growthStage(_ stage: PetGrowthStage) -> String {
        switch stage {
        case .hatchling: return text("初生", "Hatchling", "ハッチリング", "새싹")
        case .companion: return text("伙伴", "Companion", "コンパニオン", "동료")
        case .scout: return text("探索者", "Scout", "スカウト", "스카우트")
        case .hero: return text("英雄", "Hero", "ヒーロー", "히어로")
        case .legend: return text("传说", "Legend", "レジェンド", "전설")
        }
    }

    static func achievement(_ item: DesktopPetAchievement) -> String {
        switch item {
        case .firstSession: return text("第一次完成", "First completion")
        case .sessions10: return text("完成 10 次", "10 completions")
        case .sessions50: return text("完成 50 次", "50 completions")
        case .sessions100: return text("完成 100 次", "100 completions")
        case .tokens1M: return text("100 万 Token", "1M tokens")
        case .tokens10M: return text("1000 万 Token", "10M tokens")
        case .tokens50M: return text("5000 万 Token", "50M tokens")
        case .level5: return text("等级 5", "Level 5")
        case .level10: return text("等级 10", "Level 10")
        case .level20: return text("等级 20", "Level 20")
        case .streak3: return text("连续 3 天", "3-day streak")
        case .streak7: return text("连续 7 天", "7-day streak")
        case .nightOwl: return text("夜间伙伴", "Night owl")
        case .earlyBird: return text("清晨伙伴", "Early bird")
        }
    }

    static func achievementRequirement(_ item: DesktopPetAchievement) -> String {
        switch item {
        case .firstSession: return text("完成 1 个 Agent 会话", "Complete 1 agent session")
        case .sessions10: return text("完成 10 个 Agent 会话", "Complete 10 agent sessions")
        case .sessions50: return text("完成 50 个 Agent 会话", "Complete 50 agent sessions")
        case .sessions100: return text("完成 100 个 Agent 会话", "Complete 100 agent sessions")
        case .tokens1M: return text("累计 100 万 Token", "Use 1M total tokens")
        case .tokens10M: return text("累计 1000 万 Token", "Use 10M total tokens")
        case .tokens50M: return text("累计 5000 万 Token", "Use 50M total tokens")
        case .level5: return text("宠物达到等级 5", "Reach pet level 5")
        case .level10: return text("宠物达到等级 10", "Reach pet level 10")
        case .level20: return text("宠物达到等级 20", "Reach pet level 20")
        case .streak3: return text("连续活跃 3 天", "Be active for 3 days in a row")
        case .streak7: return text("连续活跃 7 天", "Be active for 7 days in a row")
        case .nightOwl: return text("23:00–04:59 有活动", "Be active from 11 PM–4:59 AM")
        case .earlyBird: return text("05:00–07:59 有活动", "Be active from 5–7:59 AM")
        }
    }
}

struct DesktopPetSpriteView: View {
    let pack: PetPack
    let mood: DesktopPetMood
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.frameImage(for: pack, mood: mood) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.25)
                    .foregroundStyle(.cyan)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(pack.name)
    }

    private static var sourceImageCache: [String: NSImage] = [:]
    private static var frameImageCache: [String: NSImage] = [:]

    private static func frameImage(for pack: PetPack, mood: DesktopPetMood) -> NSImage? {
        let key = "\(pack.id)-\(pack.spritePath)-\(pack.columns)-\(mood.rawValue)"
        if let cached = frameImageCache[key] { return cached }
        guard let image = sourceImage(for: pack), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let columns = max(pack.columns, 1)
        let frame = pack.frameIndex(for: mood)
        let width = image.size.width / CGFloat(columns)
        let source = NSRect(
            x: min(CGFloat(frame) * width, max(image.size.width - width, 0)),
            y: 0,
            width: width,
            height: image.size.height
        )
        let cropped = NSImage(size: source.size)
        cropped.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: source.size),
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        cropped.unlockFocus()
        frameImageCache[key] = cropped
        return cropped
    }

    private static func sourceImage(for pack: PetPack) -> NSImage? {
        let key = "\(pack.id)-\(pack.spritePath)"
        if let cached = sourceImageCache[key] { return cached }
        let url: URL?
        if pack.bundled {
            let resource = (pack.spritePath as NSString).deletingPathExtension
            url = Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "Pets")
        } else {
            url = URL(fileURLWithPath: pack.spritePath)
        }
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        sourceImageCache[key] = image
        return image
    }
}

struct DesktopPetFloatingView: View {
    @ObservedObject var store: DesktopPetStore
    let onShowHUD: () -> Void

    @State private var hovering = false
    @State private var isDragging = false
    @State private var showHearts = false

    private var petSize: CGFloat { CGFloat(store.preferences.petSize) }
    private var showsBubble: Bool {
        store.preferences.showMessages && (hovering || store.mood != .idle || !store.activeSessions.isEmpty)
    }

    var body: some View {
        // The speech bubble is an overlay, not a VStack sibling of the pet.
        // Keeping the hit target in a fixed place prevents a mouse-enter event
        // from moving the pet out from under the pointer, which previously
        // caused an enter/exit loop and a visibly flashing bubble.
        ZStack(alignment: .bottom) {
            petBody

            if showsBubble {
                bubbleBody
                    .allowsHitTesting(false)
                    .offset(y: -(petSize + 8))
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(8)
        .opacity(store.preferences.opacity)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: store.mood)
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if store.activeSessions.isEmpty {
            PetSpeechBubble(text: store.speech)
        } else {
            PetAgentActivityBubble(sessions: store.activeSessions)
        }
    }

    private var petBody: some View {
        ZStack(alignment: .topTrailing) {
            DesktopPetSpriteView(
                pack: store.activePack,
                mood: store.mood,
                size: petSize
            )
            if store.mood == .working {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.cyan)
                    .offset(x: 1, y: 4)
                    .transition(.opacity.combined(with: .scale))
            }
            if store.mood == .blocked {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.orange)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    .offset(x: 2, y: 4)
                    .transition(.opacity.combined(with: .scale))
            }
            if showHearts {
                PetHeartBurst()
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale))
            }

            // A native tracking surface keeps the panel movement on the
            // AppKit mouse-event path.  SwiftUI's DragGesture is excellent
            // inside a fixed window, but can feel sticky when it is also
            // responsible for moving that window every frame.
            DesktopPetNativeInteractionSurface(
                onTap: {
                    guard !isDragging else { return }
                    showHearts = true
                    store.feed()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                        showHearts = false
                    }
                },
                onDragStateChanged: { dragging in
                    isDragging = dragging
                },
                onHoverChanged: { hovering = $0 }
            )
            .frame(width: petSize, height: petSize)
        }
        .frame(width: petSize, height: petSize)
        .contentShape(Circle())
        .contextMenu {
            Button(PetUI.text("查看宠物面板", "Show Pet HUD")) {
                onShowHUD()
            }
            Button(PetUI.text("喂一喂", "Feed")) {
                store.feed()
            }
            Divider()
            Button(PetUI.text("隐藏桌面宠物", "Hide Desktop Pet")) {
                store.setEnabled(false)
            }
        }
    }
}

/// A transparent AppKit view that owns a mouse sequence from down to up.  The
/// pointer is measured in screen coordinates, so moving the panel itself never
/// changes the drag baseline and cannot introduce the small back-and-forth jump
/// that a local-coordinate SwiftUI gesture can produce.
private struct DesktopPetNativeInteractionSurface: NSViewRepresentable {
    let onTap: () -> Void
    let onDragStateChanged: (Bool) -> Void
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> PetNativeInteractionView {
        let view = PetNativeInteractionView()
        view.onTap = onTap
        view.onDragStateChanged = onDragStateChanged
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ view: PetNativeInteractionView, context: Context) {
        view.onTap = onTap
        view.onDragStateChanged = onDragStateChanged
        view.onHoverChanged = onHoverChanged
    }
}

private final class PetNativeInteractionView: NSView {
    var onTap: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var mouseDownPoint: NSPoint?
    private var isDragging = false
    private let dragThreshold: CGFloat = 3
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.openHand.set()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        NSCursor.arrow.set()
        onHoverChanged?(false)
    }

    override func cursorUpdate(with event: NSEvent) {
        (isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = screenPoint(for: event)
        isDragging = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint = mouseDownPoint else { return }
        let currentPoint = screenPoint(for: event)
        if !isDragging {
            let deltaX = currentPoint.x - downPoint.x
            let deltaY = currentPoint.y - downPoint.y
            guard hypot(deltaX, deltaY) >= dragThreshold else { return }
            isDragging = true
            NSCursor.closedHand.set()
            onDragStateChanged?(true)
            DesktopPetWindowController.shared.beginDrag(at: downPoint)
        }
        DesktopPetWindowController.shared.updateDrag(to: currentPoint)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            if isDragging {
                isDragging = false
                onDragStateChanged?(false)
            }
            NSCursor.openHand.set()
        }
        if isDragging {
            DesktopPetWindowController.shared.endDrag()
        } else {
            onTap?()
        }
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }
}

private struct PetHeartBurst: View {
    var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .offset(x: -18, y: -18)
            Image(systemName: "heart.fill")
                .foregroundStyle(.purple)
                .font(.system(size: 10))
                .offset(x: 15, y: -26)
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
                .font(.system(size: 11))
                .offset(x: 2, y: -40)
        }
        .font(.system(size: 13))
    }
}

private struct PetSpeechBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: -1) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            Triangle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 12, height: 7)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PetAgentActivityBubble: View {
    let sessions: [PetActiveAgentSession]

    private var displayedSessions: [PetActiveAgentSession] {
        sessions.sorted {
            if $0.mood != $1.mood { return Self.priority(for: $0.mood) < Self.priority(for: $1.mood) }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private static func priority(for mood: DesktopPetMood) -> Int {
        switch mood {
        case .blocked: return 0
        case .waiting: return 1
        case .working: return 2
        case .celebrating, .resting, .idle: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(displayedSessions.prefix(3))) { session in
                PetAgentSessionRow(session: session, compact: true)
            }
            if sessions.count > 3 {
                Text("+\(sessions.count - 3) \(PetUI.text("个 Agent", "more agents"))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 240, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

private struct PetAgentSessionRow: View {
    let session: PetActiveAgentSession
    var compact = false

    private var stateColor: Color {
        switch session.mood {
        case .blocked: return .red
        case .waiting: return .orange
        case .working: return .cyan
        case .celebrating, .resting, .idle: return .secondary
        }
    }

    private var stateTitle: String {
        switch session.mood {
        case .blocked: return PetUI.text("受阻", "Blocked")
        case .waiting: return PetUI.text("等待", "Waiting")
        case .working: return PetUI.text("工作中", "Working")
        case .celebrating, .resting, .idle: return PetUI.text("空闲", "Idle")
        }
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            HStack(spacing: 6) {
                if let provider = session.provider {
                    ProviderLogo(
                        provider: provider,
                        size: compact ? 14 : 17,
                        fallbackColor: ProviderPalette.color(for: provider)
                    )
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        .foregroundStyle(stateColor)
                        .frame(width: compact ? 14 : 17, height: compact ? 14 : 17)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 5, height: 5)
                        Text(stateTitle)
                            .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                        if let model = session.model, !model.isEmpty {
                            Text(model)
                                .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(stateColor.opacity(0.16), in: Capsule())
                        }
                    }
                    if let message = session.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let projectPath = session.projectPath {
                        Text(URL(fileURLWithPath: projectPath).lastPathComponent)
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                Text(Self.elapsed(since: session.stateSince, now: timeline.date))
                    .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func elapsed(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h\(minutes % 60)m"
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct DesktopPetHUDView: View {
    @ObservedObject var store: DesktopPetStore
    let onOpenSettings: () -> Void
    @State private var showsAchievementDetails = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                care
                if !store.activeSessions.isEmpty {
                    activeAgents
                }
                history
                if !store.quotaRows.isEmpty {
                    liveQuotas
                }
                achievements
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(maxHeight: 560)
        .frame(width: 330)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            DesktopPetSpriteView(pack: store.activePack, mood: store.mood, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.activePack.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("\(PetUI.growthStage(store.progress.stage)) · \(PetUI.text("等级", "Level")) \(store.progress.level)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.progress.totalXP) XP")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
        }
    }

    private var care: some View {
        VStack(alignment: .leading, spacing: 9) {
            PetHUDMetric(
                icon: "sparkles",
                label: PetUI.text("成长进度", "Growth"),
                value: "\(store.progress.xpIntoCurrentLevel) / \(store.progress.xpForNextLevel) XP",
                progress: store.nextLevelProgress,
                color: .cyan
            )
            PetHUDMetric(
                icon: "bolt.heart.fill",
                label: PetUI.text("能量", "Energy"),
                value: "\(store.energyPercent)%",
                progress: Double(store.energyPercent) / 100,
                color: .pink
            )
            HStack(spacing: 10) {
                Label("\(store.progress.dailyStreak)", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                Text(PetUI.text("连续活跃天数", "active-day streak"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.progress.completedSessions)")
                    .fontWeight(.bold)
                Text(PetUI.text("完成", "completed"))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(PetUI.text("最近 7 天活跃度", "Seven-day activity"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 7) {
                let maximum = max(store.recentHistory.map(\.tokens).max() ?? 0, 1)
                ForEach(store.recentHistory) { day in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.95), .blue.opacity(0.55)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 22, height: max(4, 38 * day.tokens / maximum))
                        Text(Self.dayFormatter.string(from: day.day))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 59)
        }
    }

    private var activeAgents: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(PetUI.text("正在运行的 Agent", "Active agents"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.activeSessions.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            ForEach(store.activeSessions.sorted(by: { $0.updatedAt > $1.updatedAt })) { session in
                PetAgentSessionRow(session: session)
            }
        }
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsAchievementDetails.toggle()
                }
            } label: {
                HStack {
                    Label(
                        "\(store.achievements.count) / \(DesktopPetAchievement.allCases.count)",
                        systemImage: "medal.fill"
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.yellow)
                    Text(PetUI.text("成就", "Achievements"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(PetUI.text(showsAchievementDetails ? "收起" : "查看全部", showsAchievementDetails ? "Hide" : "View all"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Image(systemName: showsAchievementDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAchievementDetails {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                    alignment: .leading,
                    spacing: 7
                ) {
                    ForEach(DesktopPetAchievement.allCases) { achievement in
                        PetAchievementTile(
                            achievement: achievement,
                            isUnlocked: store.achievements.contains(achievement)
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var liveQuotas: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(PetUI.text("实时额度", "Live quotas"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(store.quotaRows) { row in
                HStack(spacing: 6) {
                    ProviderLogo(
                        provider: row.provider,
                        size: 15,
                        fallbackColor: ProviderPalette.color(for: row.provider)
                    )
                    Text(L10n.providerName(row.provider))
                        .lineLimit(1)
                    Text(row.window.title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(row.remainingPercent)%")
                        .fontWeight(.bold)
                    if let resetAt = row.resetAt {
                        Text(resetAt, style: .relative)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.feed()
            } label: {
                Label(PetUI.text("喂一喂", "Feed"), systemImage: "heart.fill")
            }
            .buttonStyle(.borderedProminent)
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button(PetUI.text("隐藏", "Hide")) {
                store.setEnabled(false)
            }
            .buttonStyle(.link)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()
}

private struct PetAchievementTile: View {
    let achievement: DesktopPetAchievement
    let isUnlocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isUnlocked ? Color.yellow : Color.secondary.opacity(0.8))
                .frame(width: 15, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(PetUI.achievement(achievement))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(PetUI.achievementRequirement(achievement))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
        .background(
            isUnlocked ? Color.yellow.opacity(0.10) : Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isUnlocked ? Color.yellow.opacity(0.20) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("\(PetUI.achievement(achievement)) · \(PetUI.achievementRequirement(achievement))")
    }
}

private struct PetHUDMetric: View {
    let icon: String
    let label: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 15)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(color)
        }
    }
}
