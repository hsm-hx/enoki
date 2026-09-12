import AppKit
import Dispatch
import EnokiCore
import os

/// 会話機能がマスコット本体に問い合わせること
@MainActor
protocol ConversationHost: AnyObject {
    /// 吹き出しの親にするウィンドウ
    var conversationParentWindow: NSWindow? { get }
    /// ドラッグ中・リアクション中（会話を差し込まない）
    var isBusyForConversation: Bool { get }
    /// ユーザーが離席中（マスコットがスリープ状態）
    var isUserAwayForConversation: Bool { get }
    /// マスコットが非表示
    var isMascotHiddenForConversation: Bool { get }
    /// 行に紐づいた reaction アニメーションを再生する
    func playConversationReaction(named name: String)
}

/// 声かけの司令塔。60 秒ごとに「話してよいか」を判定し、会話を選んで吹き出しに流す。
///
/// **監視は一切しない。** 見ているのは時刻・自分の状態・設定だけで、
/// キー入力・画面・ファイル・アクティブアプリ・クリップボードは読まない。
@MainActor
final class ConversationCoordinator: ConversationPresenterDelegate {

    private static let logger = Logger(subsystem: "com.enoki.mascot", category: "conversation")

    /// 判定の周期
    static let tickInterval: TimeInterval = 60
    /// 開発用: 起動直後に一度しゃべらせる
    static let debugSpeakEnvironmentKey = "ENOKI_DEBUG_SPEAK_ON_LAUNCH"
    /// 開発用: 起動直後にしゃべらせる会話 id を指定する（未指定なら ambient / pair からランダム）
    static let debugSpeakIDEnvironmentKey = "ENOKI_DEBUG_SPEAK_ID"

    private let settings: AppSettings
    private weak var host: ConversationHost?
    private let presenter = ConversationPresenter()
    private let scheduler: ConversationScheduler
    private var provider: LocalDialogueProvider?
    private var timer: DispatchSourceTimer?
    /// 会話を選んでいる最中（async のあいだ二重に走らせない）
    private var isPicking = false

    private(set) var dialogueSourceURL: URL?

    init(settings: AppSettings, host: ConversationHost) {
        self.settings = settings
        self.host = host
        self.scheduler = ConversationScheduler(
            sessionStart: Date(),
            history: ConversationHistory.decoded(from: settings.conversationHistoryData),
            activityMode: settings.activityMode,
            quietMode: settings.quietMode,
            workEndHour: settings.workEndHour)
        presenter.delegate = self
    }

    // MARK: - 起動 / 終了

    func start(skinDirectory: URL?) {
        loadDialogue(skinDirectory: skinDirectory)
        guard provider != nil else { return }
        startTimer()
        if ProcessInfo.processInfo.environment[Self.debugSpeakEnvironmentKey] == "1" {
            Self.logger.info("\(Self.debugSpeakEnvironmentKey, privacy: .public)=1: 起動直後に 1 回しゃべります")
            let debugID = ProcessInfo.processInfo.environment[Self.debugSpeakIDEnvironmentKey]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated {
                    if let debugID,
                       let conversation = self.provider?.dialogueSet.conversations.first(where: { $0.id == debugID }) {
                        self.present(conversation)
                    } else {
                        self.speakNow()
                    }
                }
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        presenter.cancel()
        saveHistory()
    }

    /// スキンを読み直したとき、台詞も読み直す
    func reloadDialogue(skinDirectory: URL?) {
        loadDialogue(skinDirectory: skinDirectory)
        if provider != nil, timer == nil { startTimer() }
    }

    // MARK: - 台詞の読み込み

    /// 解決順: (1) 使用中スキンフォルダの dialogue.json (2) 内蔵 Resources/DialogueText/dialogue.json
    private func loadDialogue(skinDirectory: URL?) {
        var candidates: [URL] = []
        if let skinDirectory {
            candidates.append(skinDirectory.appendingPathComponent(DialogueLoader.fileName))
        }
        if let bundled = BundledResources.dialogueURL {
            candidates.append(bundled)
        }

        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let result = try DialogueLoader.load(url: url)
                for issue in result.issues {
                    Self.logger.error("台詞を 1 件読み飛ばしました: \(issue.localizedDescription, privacy: .public)")
                }
                guard !result.set.isEmpty else {
                    Self.logger.error("台詞が 0 件でした: \(url.path, privacy: .public)")
                    continue
                }
                if let provider {
                    provider.update(dialogueSet: result.set)
                } else {
                    provider = LocalDialogueProvider(dialogueSet: result.set)
                }
                dialogueSourceURL = url
                Self.logger.info("台詞を読み込みました: \(url.path, privacy: .public) \(result.set.conversations.count)件")
                return
            } catch {
                Self.logger.error("台詞を読み込めません \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        provider = nil
        dialogueSourceURL = nil
        Self.logger.error("台詞ファイルが見つからないため、会話機能を無効にします")
    }

    // MARK: - タイマー

    private func startTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + Self.tickInterval,
                        repeating: Self.tickInterval,
                        leeway: .seconds(10))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = source
        source.resume()
    }

    private func tick() {
        guard let provider, let host else { return }
        let now = Date()

        // until が過ぎていたら自動的に通常へ戻す
        if settings.quietMode.isExpired(at: now) {
            settings.quietMode = .normal
        }
        guard !presenter.isPlaying, !isPicking else { return }

        syncScheduler()
        let historyBefore = scheduler.history
        let categories = scheduler.evaluate(now: now)
        // quiet 明けの「最終会話時刻」更新など、変化したときだけ保存する
        if scheduler.history != historyBefore { saveHistory() }
        guard !categories.isEmpty else { return }
        // ドラッグ中・リアクション中は今回の tick を捨てる
        guard !host.isBusyForConversation else {
            Self.logger.debug("取り込み中なので今回の声かけを見送りました")
            return
        }

        pick(context: makeContext(now: now,
                                  allowed: Set(categories),
                                  trigger: .scheduled),
             provider: provider)
    }

    // MARK: - 手動

    /// メニューの「ちょっと話して」。quiet も間隔も無視して必ず反応する。
    func speakNow() {
        guard let provider else {
            Self.logger.error("台詞が読み込まれていないので話せません")
            return
        }
        guard let host, !host.isMascotHiddenForConversation else {
            Self.logger.info("マスコットが非表示なので吹き出しは出しません")
            return
        }
        presenter.cancel()
        isPicking = false
        pick(context: makeContext(now: Date(), allowed: [.ambient, .pair], trigger: .manual),
             provider: provider)
    }

    // MARK: - 会話の選択と再生

    private func makeContext(now: Date,
                             allowed: Set<DialogueCategory>,
                             trigger: ConversationContext.Trigger) -> ConversationContext {
        let history = scheduler.history
        let minutes = Int(now.timeIntervalSince(scheduler.sessionStart) / 60)
        return ConversationContext(now: now,
                                   allowedCategories: allowed,
                                   recentlyShownIDs: history.recentIDs,
                                   lastCategory: history.lastCategory,
                                   lastShownAt: history.lastShownAt,
                                   trigger: trigger,
                                   activityMode: settings.activityMode,
                                   minutesSinceSessionStart: max(0, minutes))
    }

    private func pick(context: ConversationContext, provider: LocalDialogueProvider) {
        isPicking = true
        Task { [weak self] in
            let conversation = await provider.nextConversation(context: context)
            guard let self else { return }
            self.isPicking = false
            guard let conversation else {
                Self.logger.debug("条件に合う会話がありませんでした")
                return
            }
            self.present(conversation)
        }
    }

    private func present(_ conversation: Conversation) {
        guard let host,
              let window = host.conversationParentWindow,
              !host.isMascotHiddenForConversation else { return }
        scheduler.record(conversation, at: Date())
        saveHistory()
        presenter.play(conversation, over: window)
    }

    // MARK: - 設定の反映

    private func syncScheduler() {
        scheduler.activityMode = settings.activityMode
        scheduler.quietMode = settings.quietMode
        scheduler.workEndHour = settings.workEndHour
        scheduler.setUserAway(host?.isUserAwayForConversation ?? false, now: Date())
        scheduler.isMascotHidden = !settings.isVisible || (host?.isMascotHiddenForConversation ?? true)
    }

    /// 仕事中モードが切り替わった
    func activityModeChanged() {
        scheduler.activityMode = settings.activityMode
        if settings.activityMode == .work {
            // 仕事中モードを入れた時刻を新しいセッション開始にする
            scheduler.restartSession(at: Date())
        }
        Self.logger.info("仕事中モード: \(self.settings.activityMode.rawValue, privacy: .public)")
    }

    /// 表示 / 非表示が切り替わった
    func visibilityChanged() {
        if !settings.isVisible { presenter.cancel() }
    }

    private func saveHistory() {
        settings.conversationHistoryData = scheduler.history.encoded()
    }

    // MARK: - ConversationPresenterDelegate

    func presenter(_ presenter: ConversationPresenter, willShow line: DialogueLine) {
        guard let reaction = line.reaction, !reaction.isEmpty else { return }
        host?.playConversationReaction(named: reaction)
    }

    func presenter(_ presenter: ConversationPresenter, didFinish conversation: Conversation, cancelled: Bool) {
        Self.logger.info("会話を終了: \(conversation.id, privacy: .public) cancelled=\(cancelled)")
    }
}
