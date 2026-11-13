import AppKit
import CodexBarCore
import SwiftUI

enum SettingsWindowIdentity {
    static let identifier = "com.steipete.codexbar.settings"
    static let frameAutosaveName = "CodexBar.SettingsWindow"
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Outcome: Equatable {
        case created
        case reused
        case failed
    }

    typealias WindowFactory = @MainActor () -> NSWindow?
    typealias WindowAction = @MainActor (NSWindow) -> Void

    private let selection: PreferencesSelection
    private let makeWindow: WindowFactory
    private let prepareToPresent: @MainActor () -> Void
    private let registerWindow: WindowAction
    private let presentWindow: WindowAction
    private let didPresentWindow: WindowAction
    private let presentationFailed: @MainActor () -> Void
    private let logger = CodexBarLog.logger(LogCategories.app)
    private var openCodexAccess: OpenCodexAccessSettings?
    private var frameWhenClosed: NSRect?

    init(
        selection: PreferencesSelection,
        makeWindow: @escaping WindowFactory,
        prepareToPresent: @escaping @MainActor () -> Void = {
            DockIconController.shared.prepareToOpenSettings()
        },
        registerWindow: @escaping WindowAction = { window in
            DockIconController.shared.registerSettingsWindow(window)
        },
        presentWindow: @escaping WindowAction = { window in
            SettingsWindowStageBehavior.present(window)
        },
        didPresentWindow: @escaping WindowAction = { window in
            DockIconController.shared.settingsWindowDidPresent(window)
        },
        presentationFailed: @escaping @MainActor () -> Void = {
            DockIconController.shared.settingsWindowPresentationFailed()
        })
    {
        self.selection = selection
        self.makeWindow = makeWindow
        self.prepareToPresent = prepareToPresent
        self.registerWindow = registerWindow
        self.presentWindow = presentWindow
        self.didPresentWindow = didPresentWindow
        self.presentationFailed = presentationFailed
        super.init(window: nil)
    }

    convenience init(
        settings: SettingsStore,
        store: UsageStore,
        cloudSyncState: CloudSyncState,
        updater: UpdaterProviding,
        selection: PreferencesSelection,
        openCodexAccess: OpenCodexAccessSettings? = nil,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator,
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator,
        runProviderLoginFlow: @escaping @MainActor (UsageProvider) async -> Void)
    {
        self.init(selection: selection) {
            let rootView = PreferencesView(
                settings: settings,
                store: store,
                cloudSyncState: cloudSyncState,
                updater: updater,
                selection: selection,
                openCodexAccess: openCodexAccess,
                managedCodexAccountCoordinator: managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: codexAccountPromotionCoordinator,
                runProviderLoginFlow: runProviderLoginFlow)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: SettingsPane.windowWidth,
                    height: SettingsPane.windowHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.contentViewController = hostingController
            window.title = selection.title
            SettingsWindowToolbar.configure(window)
            SettingsWindowSizing.enforceMinimumSize(window)
            if !window.setFrameUsingName(SettingsWindowIdentity.frameAutosaveName) {
                window.center()
            }
            window.setFrameAutosaveName(SettingsWindowIdentity.frameAutosaveName)
            return window
        }
        self.openCodexAccess = openCodexAccess
        openCodexAccess?.dashboard.didActivate = { [weak self] in
            self?.refreshOpenCodexIfVisible()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.settingsWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil)
    }

    @objc private func settingsWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        self.refreshOpenCodexIfVisible()
    }

    func refreshOpenCodexIfVisible() {
        guard let feature = self.openCodexAccess,
              self.window?.isVisible == true,
              self.selection.pane == .opencodex
        else { return }
        Task { [weak self] in
            guard let self else { return }
            await feature.activate(isSettingsVisible: self.window?.isVisible == true, selectedPane: self.selection.pane)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        guard self.isWindowLoaded,
              let window = notification.object as? NSWindow,
              window === self.window
        else { return }
        let frame = window.frame
        self.frameWhenClosed = frame
        // Detaching SwiftUI can resize the window and change its autosaved frame.
        window.contentViewController = nil
        window.contentView = NSView()
        window.setFrame(frame, display: false)
        self.window = nil
    }

    @discardableResult
    func open(pane: SettingsPane?) -> Outcome {
        if let pane {
            self.selection.pane = pane
        }
        if pane == .about {
            self.selection.requestAboutRoot()
        }

        self.prepareToPresent()
        let outcome: Outcome
        let window: NSWindow
        if self.isWindowLoaded, let existingWindow = self.window {
            window = existingWindow
            outcome = .reused
        } else if let createdWindow = self.makeWindow() {
            createdWindow.identifier = NSUserInterfaceItemIdentifier(SettingsWindowIdentity.identifier)
            SettingsWindowStageBehavior.applyCollectionBehavior(createdWindow)
            createdWindow.isReleasedWhenClosed = false
            createdWindow.delegate = self
            if let frameWhenClosed {
                createdWindow.setFrame(frameWhenClosed, display: false)
            }
            self.window = createdWindow
            window = createdWindow
            outcome = .created
        } else {
            self.presentationFailed()
            self.logger.error("Failed to create Settings window")
            return .failed
        }

        self.registerWindow(window)
        self.presentWindow(window)
        self.didPresentWindow(window)
        self.logger.info(
            "Settings window presented",
            metadata: [
                "outcome": outcome == .created ? "created" : "reused",
                "pane": self.selection.pane.persistenceToken,
            ])
        return outcome
    }
}
