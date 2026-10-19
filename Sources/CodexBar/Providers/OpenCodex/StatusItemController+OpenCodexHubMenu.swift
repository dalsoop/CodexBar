import AppKit
import CodexBarCore

/// Identifies one hub account a menu row switches to. Holds only the masked email and id suffix.
final class OpenCodexHubMenuSelection: NSObject {
    let provider: UsageProvider
    let account: OpenCodexHubAccount
    let label: String

    init(provider: UsageProvider, account: OpenCodexHubAccount, label: String) {
        self.provider = provider
        self.account = account
        self.label = label
    }
}

extension StatusItemController {
    /// Adds the hub rows when the card reads an opencodex hub pool.
    func addOpenCodexHubMenuItemsIfNeeded(provider: UsageProvider, to menu: NSMenu) {
        guard self.store.usesOpenCodexHub(for: provider) else { return }
        self.addOpenCodexHubMenuItems(provider: provider, to: menu)
    }

    /// Notices and the account switcher of a Codex or Grok card that reads an opencodex hub pool. The
    /// active account's quota renders as the provider card below these rows.
    func addOpenCodexHubMenuItems(provider: UsageProvider, to menu: NSMenu) {
        guard let state = self.store.openCodexHubCardState(for: provider) else {
            self.addOpenCodexHubNotice(L("Reading the opencodex hub…"), to: menu)
            return
        }
        guard let pool = state.pool else {
            if let error = state.lastError {
                self.addOpenCodexHubNotice(error, to: menu)
            }
            return
        }
        for line in OpenCodexHubPresentation.poolNotices(pool) {
            self.addOpenCodexHubNotice(line, to: menu)
        }
        if let error = state.lastError {
            self.addOpenCodexHubNotice(error, to: menu)
        }
        for line in state.switchStatus.menuLines(hidePersonalInfo: self.settings.hidePersonalInfo) {
            self.addOpenCodexHubNotice(line, to: menu)
        }
        guard !pool.accounts.isEmpty else { return }

        let canSwitchNow = pool.switchable && !state.isSwitching && !state.switchStatus.isPending
        let switcher = NSMenuItem(
            title: pool.switchable ? L("Switch opencodex hub account") : L("opencodex hub accounts"),
            action: nil,
            keyEquivalent: "")
        let submenu = NSMenu()
        let hidePersonalInfo = self.settings.hidePersonalInfo
        for (index, account) in pool.accounts.enumerated() {
            let label = OpenCodexHubPresentation.label(
                for: account,
                hidePersonalInfo: hidePersonalInfo,
                ordinal: index + 1)
            let item = NSMenuItem(
                title: OpenCodexHubPresentation.menuTitle(for: account, label: label),
                action: #selector(self.selectOpenCodexHubAccount(_:)),
                keyEquivalent: "")
            item.target = self
            item.state = account.isActive ? .on : .off
            item.representedObject = OpenCodexHubMenuSelection(provider: provider, account: account, label: label)
            item.isEnabled = canSwitchNow && pool.canSwitch(to: account)
            submenu.addItem(item)
        }
        if !pool.switchable {
            submenu.addItem(.separator())
            self.addOpenCodexHubNotice(
                pool.switchReason ?? OpenCodexHubPresentation.defaultSwitchReason(hubName: pool.hubName),
                to: submenu)
        }
        submenu.autoenablesItems = false
        switcher.submenu = submenu
        menu.addItem(switcher)
        menu.addItem(.separator())
    }

    @objc func selectOpenCodexHubAccount(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? OpenCodexHubMenuSelection,
              let state = self.store.openCodexHubCardState(for: selection.provider),
              let pool = state.pool,
              pool.canSwitch(to: selection.account)
        else { return }
        // A hub switch moves every Mac that uses the hub, so it is confirmed outside the open menu first.
        sender.menu?.supermenu?.cancelTracking()
        sender.menu?.cancelTracking()
        let isHubLocal = pool.isHubLocal
        Task { @MainActor [weak self] in
            guard let self,
                  Self.confirmOpenCodexHubCardSwitch(selection: selection, isHubLocal: isHubLocal)
            else { return }
            self.store.switchOpenCodexHubAccount(
                selection.account,
                provider: selection.provider,
                label: selection.label,
                progressDidChange: { [weak self] in self?.invalidateMenus() })
        }
    }

    private static func confirmOpenCodexHubCardSwitch(selection: OpenCodexHubMenuSelection, isHubLocal: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Switch the opencodex hub to %@?", selection.label)
        alert.informativeText = OpenCodexHubPresentation.confirmationDetails(
            account: selection.account,
            isHubLocal: isHubLocal,
            everyMacMoves: L("Every Mac that uses this hub moves to this account on its next request."))
        alert.addButton(withTitle: L("Switch Account..."))
        let cancel = alert.addButton(withTitle: L("Cancel"))
        cancel.keyEquivalent = "\u{1B}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func addOpenCodexHubNotice(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}
