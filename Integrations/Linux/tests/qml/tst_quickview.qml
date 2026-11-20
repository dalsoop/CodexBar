import QtQuick
import QtTest
import "../../qml" as Desktop

TestCase {
    id: testCase
    name: "QuickView"
    when: windowShown
    QtObject {
        id: desktop
        property var settings: ({showCosts: true, quotaDisplay: "remaining", resetDisplay: "countdown",
            showPace: true, warningColors: true, notifyThreshold: 10})
        property var entries: [{provider: "codex", accountLabel: "", plan: "Synthetic plan",
            windows: [{label: "Session", remaining: 60, resetsAt: "2030-01-01T00:00:00Z", pace: ""}],
            credits: null, error: "", status: "", details: []}]
        property var spending: []
        property bool busy: false
        property bool stale: false
        property string updated: "just now"
        property string error: ""
        property bool costBusy: false
        property string costError: ""
        property var hub: ({})
        property var prepared: []
        property var confirmed: []
        property int cancelled: 0
        signal changed()
        function refresh() {}
        function showWindow(page) {}
        function prepareHubSwitch(provider, index) {
            prepared = prepared.concat([provider + ":" + index]);
            return {ok: true, token: "synthetic-token", title: "Switch the opencodex hub to Account 2?",
                paragraphs: ["Every machine that uses this hub moves to this account on its next request.",
                    "Quota: 5h: 12% used · Weekly: 51% used"]};
        }
        function confirmHubSwitch(token) { confirmed = confirmed.concat([token]); return true; }
        function cancelHubSwitch() { cancelled += 1; }
    }
    property var view: null
    Component { id: viewComponent; Desktop.QuickView {} }

    function textItem(item, text) {
        if (item.text === text && item.visible) return item;
        for (var i = 0; i < item.children.length; ++i) {
            var found = textItem(item.children[i], text);
            if (found) return found;
        }
        return null;
    }
    function shown(text) { return textItem(view.contentItem, text) !== null; }
    // Popups render in the window overlay, outside the application content item.
    function topItem() { var item = view.contentItem; while (item.parent) item = item.parent; return item; }
    function hubView(switchable) {
        return {provider: "codex", note: "", message: "", error: "", hasPool: true, busy: false,
            header: ["Accounts: 2 · Hub list updated 1 min ago.", "Accounts are managed on the hub office."],
            notices: [], accounts: [
                {index: 0, title: "Account 1", quota: "5h: 40% used", active: true, canSwitch: false},
                {index: 1, title: "Account 2", quota: "5h: 12% used · Weekly: 51% used", active: false,
                    canSwitch: switchable}]};
    }
    function init() {
        desktop.settings = {showCosts: true, quotaDisplay: "remaining", resetDisplay: "countdown",
            showPace: true, warningColors: true, notifyThreshold: 10};
        desktop.spending = [{provider: "codex", today: 3, month: 12, tokens: 100, provenance: "local",
            coverage: "History may be incomplete", error: "Synthetic provider cost error"}];
        desktop.costError = "Local spending could not be refreshed. Previous data may be stale.";
        desktop.costBusy = false;
        desktop.hub = {};
        desktop.prepared = []; desktop.confirmed = []; desktop.cancelled = 0;
        view = createTemporaryObject(viewComponent, testCase, {visible: true});
        verify(view);
    }
    function test_retainedCostShowsRefreshError() {
        tryVerify(function() { return shown(desktop.costError); });
        verify(shown("Today $3.00  ·  Last 30 days $12.00"));
    }
    function test_partialCostShowsCoverageAndProviderError() {
        tryVerify(function() { return shown("History may be incomplete"); });
        verify(shown("Synthetic provider cost error"));
    }
    function test_firstFailureIsVisibleWithoutCachedTotals() {
        desktop.spending = [];
        tryVerify(function() { return shown(desktop.costError); });
    }
    function test_refreshingRetainedCostIsVisible() {
        desktop.costError = "";
        desktop.costBusy = true;
        tryVerify(function() { return shown("Reading local history…"); });
    }
    function test_disabledCostsHideErrorsAndTotals() {
        desktop.settings = {showCosts: false, quotaDisplay: "remaining", resetDisplay: "countdown",
            showPace: true, warningColors: true, notifyThreshold: 10};
        tryVerify(function() { return !shown("Cost across accounts"); });
        verify(!shown(desktop.costError));
    }
    function test_hubListShowsRowsAndHeader() {
        desktop.hub = {codex: hubView(true)};
        tryVerify(function() { return shown("opencodex hub accounts"); });
        verify(shown("Accounts are managed on the hub office."));
        verify(shown("Active"));
        verify(shown("5h: 12% used · Weekly: 51% used"));
    }
    function test_noHubKeepsDetailUnchanged() {
        tryVerify(function() { return shown("Cost across accounts"); });
        verify(!shown("opencodex hub accounts"));
        desktop.hub = {codex: {provider: "codex", note: "CodexBar CLI too old for hub accounts", message: "",
            error: "", hasPool: false, busy: false, header: [], notices: [], accounts: []}};
        tryVerify(function() { return shown("CodexBar CLI too old for hub accounts"); });
        verify(!shown("Switch"));
    }
    function test_switchNeedsTheConfirmationDialog() {
        desktop.hub = {codex: hubView(true)};
        tryVerify(function() { return shown("Switch"); });
        textItem(view.contentItem, "Switch").clicked();
        compare(desktop.prepared, ["codex:1"]);
        compare(desktop.confirmed, []);
        tryVerify(function() { return textItem(topItem(), "Switch the opencodex hub to Account 2?") !== null; });
        verify(textItem(topItem(), "Every machine that uses this hub moves to this account on its next request.") !== null);
        textItem(topItem(), "Cancel").clicked();
        tryVerify(function() { return desktop.cancelled === 1; });
        compare(desktop.confirmed, []);
        textItem(view.contentItem, "Switch").clicked();
        tryVerify(function() { return textItem(topItem(), "Switch Account…") !== null; });
        textItem(topItem(), "Switch Account…").clicked();
        tryVerify(function() { return desktop.confirmed.length === 1; });
        compare(desktop.confirmed, ["synthetic-token"]);
    }
    function test_disabledSwitchCannotPrepare() {
        desktop.hub = {codex: hubView(false)};
        tryVerify(function() { return shown("Switch"); });
        verify(!textItem(view.contentItem, "Switch").enabled);
    }
    function test_syntheticRender() {
        tryVerify(function() { return shown("Cost across accounts"); });
        grabImage(view.contentItem).save("quick-view-synthetic.png");
    }
}
