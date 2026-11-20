// Pure model of the opencodex hub account list, shared by the desktop backend and offline Node tests.
// The CLI (`codexbar hub accounts` / `codexbar hub switch`) owns every hub rule: this file only builds its
// arguments, parses its answers, keeps the in-memory switch status and words it as the macOS app does.
// Nothing here reads the snapshot or writes a request file.

var pendingExpiryMs = 11 * 60 * 1000;
var staleIntervalMs = 5 * 60 * 1000;
var readFailedMessage = "The opencodex hub could not be read.";
var oldCliNote = "CodexBar CLI too old for hub accounts";

function initial() {
    return {mode: "unknown", pool: null, error: "", stale: false, note: "", message: "",
        switching: false, pending: null, notice: null, noticeAccount: null, movedOn: null};
}

function copy(state) { return JSON.parse(JSON.stringify(state || initial())); }

function str(value, limit) { return typeof value === "string" ? value.slice(0, limit || 500) : ""; }

// CLI messages are shown, never logged; an email inside one is still hidden.
function redact(value) { return str(value).replace(/[^\s@]+@[^\s@]+/g, "[hidden email]"); }

// Values passed to the CLI as separate arguments; one that looks like an option is never sent.
function safeArgument(value) { return typeof value === "string" && value !== "" && value.charAt(0) !== "-"; }

// The first three items are the `timeout` wrapper the backend replaces with its own deadline.
function accountsCommand(executable, provider, pending, seconds) {
    var args = ["timeout", "--kill-after=5", String(seconds || 40), String(executable || "codexbar"),
        "hub", "accounts", "--provider", provider, "--format", "json"];
    if (pending && safeArgument(pending.requestId) && safeArgument(pending.targetIdSuffix) &&
        safeArgument(pending.targetEmail) && safeArgument(pending.requestedAt))
        args.push("--pending-request-id", pending.requestId, "--pending-target-id-suffix", pending.targetIdSuffix,
            "--pending-target-email", pending.targetEmail, "--pending-requested-at", pending.requestedAt);
    return args;
}

// `--confirm` is always sent: the backend builds this only after the user confirmed in the dialog.
function switchCommand(executable, provider, account, seconds) {
    if (!account || !safeArgument(account.idSuffix) || !safeArgument(account.email)) return [];
    return ["timeout", "--kill-after=5", String(seconds || 40), String(executable || "codexbar"),
        "hub", "switch", "--provider", provider, "--id-suffix", account.idSuffix, "--email", account.email,
        "--confirm", "--format", "json"];
}

function normalizeAccount(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    var summary = (Array.isArray(raw.quotaSummary) ? raw.quotaSummary : []).filter(function(part) {
        return part && typeof part.label === "string" && typeof part.usedPercent === "number" && isFinite(part.usedPercent);
    }).slice(0, 6).map(function(part) { return {label: part.label.slice(0, 40), usedPercent: part.usedPercent}; });
    var health = str(raw.health, 100);
    return {idSuffix: str(raw.idSuffix, 64), label: str(raw.label, 200), email: str(raw.email, 320),
        active: raw.active === true, paused: raw.paused === true,
        needsReauth: raw.needsReauth === true || health === "Reauthentication required" || health === "Verification required",
        nearLimit: raw.nearLimit === true, canSwitch: raw.canSwitch === true, quotaSummary: summary,
        usage: raw.usage && typeof raw.usage === "object" && !Array.isArray(raw.usage) ? raw.usage : null};
}

function normalizePending(raw) {
    if (!raw || typeof raw !== "object" || typeof raw.requestId !== "string") return null;
    if (["pending", "done", "refused", "failed", "expired"].indexOf(raw.resolution) === -1) return null;
    return {requestId: raw.requestId, resolution: raw.resolution, code: str(raw.code, 200), reason: redact(raw.reason)};
}

// Kinds: unavailable (no hub command in this CLI), notConfigured, noHubSource, readError, pool.
// Valid JSON that is not the contract object comes from a CLI without the command (an older CLI prints a
// JSON error array); unparsable output or a contract object with bad fields is a read error.
function parseAccounts(text, exitCode, failed, provider) {
    if (failed) return {kind: "readError", message: readFailedMessage, configured: false};
    if (exitCode === 64) return {kind: "unavailable"};
    var decoded;
    try { decoded = JSON.parse(text); } catch (error) {
        return /unknown command/i.test(String(text)) ? {kind: "unavailable"} :
            {kind: "readError", message: readFailedMessage, configured: false};
    }
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded) || decoded.schemaVersion !== 1)
        return {kind: "unavailable"};
    var malformed = {kind: "readError", message: readFailedMessage, configured: false};
    if (decoded.provider !== provider || typeof decoded.configured !== "boolean") return malformed;
    var error = decoded.error && typeof decoded.error === "object" ? decoded.error : null;
    if (!decoded.configured) return exitCode === 0 ? {kind: "notConfigured"} : malformed;
    if (error && error.code === "noHubSource") return {kind: "noHubSource", message: redact(error.message)};
    if (error) return {kind: "readError", message: redact(error.message) || readFailedMessage, configured: true};
    if (exitCode !== 0 || !Array.isArray(decoded.accounts)) return malformed;
    var accounts = decoded.accounts.slice(0, 100).map(normalizeAccount);
    if (accounts.some(function(account) { return account === null; })) return malformed;
    return {kind: "pool", pool: {
        origin: ["snapshot", "hubLocal", "linkedCopy"].indexOf(decoded.origin) !== -1 ? decoded.origin : "snapshot",
        hub: str(decoded.hub, 200), updatedAt: str(decoded.updatedAt, 64), stale: decoded.stale === true,
        switchable: decoded.switchable === true, switchReason: redact(decoded.switchReason),
        accounts: accounts, pending: normalizePending(decoded.pending)}};
}

function activeAccount(pool) {
    var accounts = pool ? pool.accounts : [];
    for (var i = 0; i < accounts.length; ++i) if (accounts[i].active) return {account: accounts[i], ordinal: i + 1};
    return null;
}

function key(account) { return account ? {idSuffix: account.idSuffix, email: account.email} : null; }

function sameKey(a, b) { return !!a && !!b && a.idSuffix === b.idSuffix && a.email === b.email; }

// A snapshot read describes the hub at `updatedAt`; a kept pool ages like the macOS card's.
function staleNow(pool, now) {
    if (!pool) return false;
    if (pool.stale) return true;
    if (pool.origin !== "snapshot") return false;
    var updated = Date.parse(pool.updatedAt);
    return !isFinite(updated) || now - updated > staleIntervalMs;
}

function finish(state, notice, account) {
    state.pending = null;
    state.notice = notice;
    state.noticeAccount = notice ? account : null;
    state.movedOn = null;
}

// Once the hub's active account is no longer the one the notice describes, say where the hub is now.
function recordMovedOn(state, pool) {
    if (!state.notice || !state.noticeAccount) return;
    var active = activeAccount(pool);
    state.movedOn = active && !sameKey(key(active.account), state.noticeAccount) ?
        {account: active.account, ordinal: active.ordinal} : null;
}

function reasonText(code, reason) { return reason || code || "No reason given"; }

function reconcile(state, pool) {
    var active = activeAccount(pool);
    var activeKey = active ? key(active.account) : null;
    if (!state.pending) { recordMovedOn(state, pool); return; }
    var answer = pool.pending;
    if (!answer || answer.requestId !== state.pending.requestId || answer.resolution === "pending") return;
    var target = state.pending.target;
    if (answer.resolution === "done") {
        finish(state, {kind: "switched", target: target}, key(target));
        recordMovedOn(state, pool);
    } else if (answer.resolution === "refused") {
        finish(state, {kind: "refused", reason: reasonText(answer.code, answer.reason)}, activeKey);
    } else if (answer.resolution === "failed") {
        finish(state, {kind: "failed", reason: reasonText(answer.code, answer.reason)}, activeKey);
    } else {
        finish(state, {kind: "expired"}, activeKey);
    }
}

// A failed read cannot postpone the request deadline or show whether the hub executed it.
function expire(previous, now) {
    var state = copy(previous);
    if (state.pending && now - state.pending.requestedAtMs > pendingExpiryMs) finish(state, {kind: "expired"}, null);
    return state;
}

function applyAccounts(previous, result, now) {
    var state = copy(previous);
    state.note = "";
    state.message = "";
    if (result.kind === "unavailable" || result.kind === "notConfigured" || result.kind === "noHubSource") {
        state.mode = result.kind === "unavailable" ? "unavailable" : "native";
        state.pool = null; state.error = ""; state.stale = false;
        if (result.kind === "unavailable") state.note = oldCliNote;
        if (result.kind === "noHubSource") state.message = result.message;
    } else if (result.kind === "readError") {
        // An earlier pool stays; a configured hub that cannot be read never brings native Codex back.
        state.error = result.message || readFailedMessage;
        if (state.pool || result.configured) state.mode = "hub";
    } else {
        state.mode = "hub";
        state.error = "";
        // A snapshot the hub stopped rewriting never replaces a current pool.
        if (result.pool.stale && state.pool && !staleNow(state.pool, now)) {
            state.stale = true;
            return expire(state, now);
        }
        state.pool = result.pool;
        state.stale = result.pool.stale;
        reconcile(state, result.pool);
    }
    return expire(state, now);
}

function beginSwitch(previous) { var state = copy(previous); state.switching = true; return state; }

// `target` is the confirmed account: idSuffix, email and the label shown when identity is visible.
function applySwitch(previous, text, exitCode, failed, provider, target, now) {
    var state = copy(previous);
    state.switching = false;
    var decoded = null;
    try { decoded = JSON.parse(text); } catch (error) { decoded = null; }
    var valid = !failed && decoded && typeof decoded === "object" && !Array.isArray(decoded) &&
        decoded.schemaVersion === 1 && decoded.provider === provider;
    var request = valid && decoded.request && typeof decoded.request === "object" ? decoded.request : null;
    var active = activeAccount(state.pool);
    if (valid && exitCode === 0 && (decoded.outcome === "switched" || decoded.outcome === "alreadyActive")) {
        finish(state, {kind: "switched", target: target}, key(target));
    } else if (valid && exitCode === 0 && decoded.outcome === "requested" && request &&
               safeArgument(request.requestId) && safeArgument(request.requestedAt)) {
        var requestedAt = Date.parse(request.requestedAt);
        finish(state, null, null);
        state.pending = {requestId: str(request.requestId, 200),
            targetIdSuffix: str(request.targetIdSuffix, 64) || target.idSuffix,
            targetEmail: str(request.targetEmail, 320) || target.email,
            requestedAt: str(request.requestedAt, 64), requestedAtMs: isFinite(requestedAt) ? requestedAt : now,
            target: target};
    } else {
        var message = valid && decoded.error && typeof decoded.error === "object" ? redact(decoded.error.message) : "";
        finish(state, {kind: "failed", reason: message || "The switch could not be requested."},
            active ? key(active.account) : null);
    }
    return state;
}

// Presentation, worded as the macOS app's OpenCodexHubPresentation and OpenCodexHubSwitchStatus.
function accountLabel(account, showIdentity, ordinal) {
    if (!showIdentity || !account.email) return "Account " + ordinal;
    return account.label && account.label !== account.email ? account.email + " (" + account.label + ")" : account.email;
}

// Percentages always describe usage, whatever the remaining/used display preference says.
function quotaSummary(account) {
    return account.quotaSummary.map(function(part) {
        return part.label + ": " + Math.round(part.usedPercent) + "% used";
    }).join(" · ");
}

function relative(value, now) {
    var minutes = Math.floor((now - Date.parse(value)) / 60000);
    if (!isFinite(minutes)) return "";
    if (minutes < 1) return "just now";
    if (minutes < 60) return minutes + " min ago";
    if (minutes < 1440) return Math.floor(minutes / 60) + " h ago";
    return Math.floor(minutes / 1440) + " d ago";
}

function headerLines(pool, now) {
    var status = ["Accounts: " + pool.accounts.length];
    if (pool.origin === "linkedCopy") {
        status.push("Read-only account list; last hub update is unknown.");
    } else if (pool.origin !== "hubLocal") {
        var updated = relative(pool.updatedAt, now);
        status.push(updated ? "Hub list updated " + updated + "." : "Last hub update is unknown.");
        if (staleNow(pool, now)) status.push("The hub list is out of date.");
    }
    var lines = [status.join(" · ")];
    if (pool.origin !== "hubLocal")
        lines.push(pool.hub ? "Accounts are managed on the hub " + pool.hub + "." : "Accounts are managed on the opencodex hub.");
    if (pool.origin === "linkedCopy") lines.push("Switching is off until the hub writes a current snapshot to this computer.");
    else if (!pool.switchable) lines.push(pool.switchReason || (pool.hub ?
        "Accounts in this pool are switched only on " + pool.hub + "." : "Accounts in this pool are switched only on the hub."));
    return lines;
}

function statusLines(state, showIdentity) {
    if (state.pending) return ["The hub is switching accounts…"];
    if (state.movedOn)
        return ["The hub has since switched to " + accountLabel(state.movedOn.account, showIdentity, state.movedOn.ordinal) + "."];
    var notice = state.notice;
    if (!notice) return [];
    if (notice.kind === "switched") return ["The hub switched to " + (showIdentity ? notice.target.label : "Account") + "."];
    if (notice.kind === "refused") return ["The hub refused the switch: " + notice.reason];
    if (notice.kind === "failed") return ["The hub could not switch: " + notice.reason];
    return ["The switch result is unknown. Refresh the hub before trying again."];
}

function switchAllowed(state, account, now) {
    return !!state.pool && state.pool.switchable && account.canSwitch && !account.active && account.idSuffix !== "" &&
        !state.switching && !state.pending && !staleNow(state.pool, now) && state.pool.origin !== "linkedCopy";
}

// What the tray popup shows under a provider's detail. Carries masked emails: never sent over IPC.
function view(state, provider, showIdentity, now) {
    var pool = state.pool;
    var accounts = pool ? pool.accounts.map(function(account, index) {
        var title = accountLabel(account, showIdentity, index + 1);
        if (account.paused) title += " (paused)";
        else if (account.needsReauth) title += " (sign-in needed)";
        return {index: index, title: title, quota: quotaSummary(account), active: account.active,
            canSwitch: switchAllowed(state, account, now)};
    }) : [];
    return {provider: provider, note: state.note, message: state.message, hasPool: !!pool,
        // The Codex entry already shows the read error; the Claude list carries it itself.
        error: provider === "codex" ? "" : state.error,
        header: pool ? headerLines(pool, now) : [], notices: pool || state.pending || state.notice ? statusLines(state, showIdentity) : [],
        accounts: accounts, busy: state.switching || !!state.pending};
}

function confirmation(state, index, showIdentity, now) {
    var account = state.pool && state.pool.accounts[index];
    if (!account || !switchAllowed(state, account, now)) return null;
    var label = accountLabel(account, showIdentity, index + 1);
    var paragraphs = ["Every machine that uses this hub moves to this account on its next request."];
    var summary = quotaSummary(account);
    if (summary) paragraphs.push("Quota: " + summary);
    if (account.nearLimit) paragraphs.push("This account has used 80% or more of a limit. The hub may switch away " +
        "again soon, or requests may stop until the limit resets.");
    if (state.pool.origin !== "hubLocal")
        paragraphs.push("This computer asks the hub to switch; the result shows after the hub's next update.");
    return {title: "Switch the opencodex hub to " + label + "?", paragraphs: paragraphs, label: label,
        account: {idSuffix: account.idSuffix, email: account.email, label: accountLabel(account, true, index + 1)}};
}

// The Codex entry while the hub serves Codex: the active account's usage through the shared row parser.
function codexEntry(state, showIdentity, rows, now) {
    if (state.mode !== "hub") return null;
    var entry = {provider: "codex", failed: true, accountLabel: "", accountNumber: 1, plan: "", status: "",
        statusLevel: "unknown", details: [], source: "opencodex", windows: [], updatedAt: "", credits: null,
        extraUsage: null, resetCredits: null, stale: false, error: state.error || readFailedMessage};
    if (!state.pool) return entry;
    var active = activeAccount(state.pool);
    if (!active) { entry.error = "No active account"; return entry; }
    if (active.account.usage) {
        try { entry = rows(JSON.stringify([{provider: "codex", source: "opencodex", usage: active.account.usage}]), showIdentity)[0]; }
        catch (error) { entry.error = "No quota windows reported."; }
    } else entry.error = "No quota windows reported.";
    entry.source = "opencodex";
    entry.accountLabel = showIdentity ? active.account.email : "";
    var stale = state.stale || staleNow(state.pool, now);
    entry.stale = stale || state.error !== "";
    // Out-of-date numbers are shown but never drive quota notifications.
    entry.failed = entry.stale;
    if (state.error) entry.error = state.error;
    else if (stale) entry.error = "The opencodex hub snapshot is out of date";
    return entry;
}

function excludesNativeCodex(state) { return !!state && state.mode === "hub"; }
