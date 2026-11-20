// Offline checks of the hub model; test_desktop.py runs this file so it is part of the Linux desktop CI job.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const hub = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('../Shared/Hub.js', import.meta.url), 'utf8'), hub);
const usage = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('../Shared/Usage.js', import.meta.url), 'utf8'), usage);
const plain = value => JSON.parse(JSON.stringify(value));
const now = Date.parse('2030-01-01T00:10:00Z');

function account(suffix, extra = {}) {
    return {idSuffix: suffix, label: 'pro', email: `a***${suffix}@example.com`, active: false, paused: false,
        needsReauth: false, health: 'Healthy', quotaUnavailable: false, nearLimit: false, canSwitch: true,
        quotaSummary: [{label: '5h', usedPercent: 12}, {label: 'Weekly', usedPercent: 51.4}],
        usage: {primary: {usedPercent: 12, windowMinutes: 300}, secondary: {usedPercent: 51, windowMinutes: 10080}},
        ...extra};
}
function response(extra = {}) {
    return JSON.stringify({schemaVersion: 1, provider: 'codex', configured: true, origin: 'snapshot', hub: 'office',
        updatedAt: '2030-01-01T00:09:00Z', stale: false, switchable: true, switchReason: null, activeIdSuffix: '1a2b',
        accounts: [account('1a2b', {active: true, canSwitch: false}), account('3c4d', {label: 'a***3c4d@example.com'})],
        lastRequests: [], error: null, ...extra});
}
const read = (state, text, code = 0, at = now) =>
    hub.applyAccounts(state, hub.parseAccounts(text, code, false, 'codex'), at);

test('commands keep the timeout wrapper, pass pending flags and always confirm a switch', () => {
    assert.deepEqual([...hub.accountsCommand('/cli', 'claude', null, 40)],
        ['timeout', '--kill-after=5', '40', '/cli', 'hub', 'accounts', '--provider', 'claude', '--format', 'json']);
    const pending = {requestId: 'r1', targetIdSuffix: '3c4d', targetEmail: 'a***3c4d@example.com',
        requestedAt: '2030-01-01T00:00:00Z'};
    assert.deepEqual([...hub.accountsCommand('/cli', 'codex', pending, 40)].slice(10), ['--pending-request-id', 'r1',
        '--pending-target-id-suffix', '3c4d', '--pending-target-email', 'a***3c4d@example.com',
        '--pending-requested-at', '2030-01-01T00:00:00Z']);
    const args = [...hub.switchCommand('/cli', 'codex', {idSuffix: '3c4d', email: 'a***3c4d@example.com'}, 40)];
    assert.ok(args.includes('--confirm'));
    assert.deepEqual(args.slice(4, 11), ['hub', 'switch', '--provider', 'codex', '--id-suffix', '3c4d', '--email']);
    assert.equal(hub.switchCommand('/cli', 'codex', {idSuffix: '--confirm', email: 'x'}, 40).length, 0);
});

test('old CLIs, missing hubs, read errors and malformed output map to distinct kinds', () => {
    assert.equal(hub.parseAccounts('', 64, false, 'codex').kind, 'unavailable');
    assert.equal(hub.parseAccounts('[{"provider":"cli","error":{"message":"Unknown command"}}]', 1, false, 'codex').kind,
        'unavailable');
    assert.equal(hub.parseAccounts('Unknown command', 1, false, 'codex').kind, 'unavailable');
    assert.equal(hub.parseAccounts('{"schemaVersion":1,"provider":"codex","configured":false,"error":null}', 0, false,
        'codex').kind, 'notConfigured');
    assert.equal(hub.parseAccounts(response({accounts: [], error: {code: 'noHubSource', message: 'No source'}}), 0,
        false, 'codex').kind, 'noHubSource');
    const failed = hub.parseAccounts(response({accounts: [], error: {code: 'readFailed', message: 'For x@y.z'}}), 1,
        false, 'codex');
    assert.deepEqual(plain(failed), {kind: 'readError', message: 'For [hidden email]', configured: true});
    for (const text of ['{"schemaVersion":1,"provider":"codex"', response({accounts: 'x'}), response({provider: 'claude'})])
        assert.equal(hub.parseAccounts(text, 0, false, 'codex').kind, 'readError');
    assert.equal(hub.parseAccounts(response(), 0, true, 'codex').kind, 'readError');
});

test('the Codex entry follows the pool, its staleness, a missing active account and read errors', () => {
    let state = read(hub.initial(), response());
    assert.ok(hub.excludesNativeCodex(state));
    let entry = hub.codexEntry(state, false, usage.rows, now);
    assert.equal(entry.source, 'opencodex');
    assert.equal(entry.accountLabel, '');
    assert.deepEqual([...entry.windows.map(window => window.remaining)], [88, 49]);
    assert.equal(hub.codexEntry(state, true, usage.rows, now).accountLabel, 'a***1a2b@example.com');
    // A stale snapshot never replaces the current pool; the entry keeps its numbers and says why.
    state = read(state, response({stale: true, accounts: [account('9z9z', {active: true})]}));
    entry = hub.codexEntry(state, false, usage.rows, now);
    assert.equal(state.pool.accounts[0].idSuffix, '1a2b');
    assert.equal(entry.error, 'The opencodex hub snapshot is out of date');
    assert.ok(entry.stale);
    state = read(state, '{broken', 0);
    assert.equal(state.pool.accounts[0].idSuffix, '1a2b');
    assert.equal(hub.codexEntry(state, false, usage.rows, now).windows.length, 2);
    assert.ok(hub.excludesNativeCodex(state));
    const none = read(hub.initial(), response({accounts: [account('3c4d')]}));
    assert.equal(hub.codexEntry(none, false, usage.rows, now).error, 'No active account');
    // A configured hub that fails without an earlier pool shows only the error; a crash does not decide.
    const client = read(hub.initial(), response({accounts: [], error: {code: 'readFailed', message: 'Missing'}}), 1);
    assert.deepEqual([client.mode, hub.codexEntry(client, false, usage.rows, now).error], ['hub', 'Missing']);
    assert.equal(read(hub.initial(), 'broken').mode, 'unknown');
    for (const native of [read(state, response({configured: false, accounts: null})),
                          read(state, response({accounts: [], error: {code: 'noHubSource', message: 'No source'}}))]) {
        assert.ok(!hub.excludesNativeCodex(native));
        assert.equal(hub.codexEntry(native, false, usage.rows, now), null);
    }
    const old = read(state, 'Unknown command', 64);
    assert.deepEqual([old.mode, old.note, hub.view(old, 'codex', false, now).accounts.length],
        ['unavailable', 'CodexBar CLI too old for hub accounts', 0]);
});

test('the list and confirmation use the macOS wording and hide identity when asked', () => {
    const state = read(hub.initial(), response({accounts: [account('1a2b', {active: true, canSwitch: false}),
        account('3c4d', {nearLimit: true}), account('5e6f', {paused: true, canSwitch: false})]}));
    const hidden = plain(hub.view(state, 'codex', false, now));
    assert.deepEqual(hidden.header, ['Accounts: 3 · Hub list updated 1 min ago.', 'Accounts are managed on the hub office.']);
    assert.deepEqual(hidden.accounts.map(row => [row.title, row.active, row.canSwitch]),
        [['Account 1', true, false], ['Account 2', false, true], ['Account 3 (paused)', false, false]]);
    assert.equal(hidden.accounts[1].quota, '5h: 12% used · Weekly: 51% used');
    assert.ok(!JSON.stringify(hidden).includes('example.com'));
    assert.equal(hub.view(state, 'codex', true, now).accounts[1].title, 'a***3c4d@example.com (pro)');
    const prompt = plain(hub.confirmation(state, 1, false, now));
    assert.equal(prompt.title, 'Switch the opencodex hub to Account 2?');
    assert.deepEqual(prompt.paragraphs, [
        'Every machine that uses this hub moves to this account on its next request.',
        'Quota: 5h: 12% used · Weekly: 51% used',
        'This account has used 80% or more of a limit. The hub may switch away again soon, or requests may stop until the limit resets.',
        "This computer asks the hub to switch; the result shows after the hub's next update."]);
    assert.equal(hub.confirmation(state, 0, false, now), null);
    const locked = read(hub.initial(), response({switchable: false, switchReason: null, hub: null}));
    const lockedView = plain(hub.view(locked, 'codex', false, now));
    assert.deepEqual(lockedView.header.slice(1), ['Accounts are managed on the opencodex hub.',
        'Accounts in this pool are switched only on the hub.']);
    assert.ok(lockedView.accounts.every(row => !row.canSwitch));
    const local = read(hub.initial(), response({origin: 'hubLocal', updatedAt: null}));
    assert.equal(hub.confirmation(local, 1, false, now).paragraphs.length, 2);
});

test('switch outcomes and pending resolutions produce the pinned notices', () => {
    const target = {idSuffix: '3c4d', email: 'a***3c4d@example.com', label: 'a***3c4d@example.com (pro)'};
    let state = read(hub.initial(), response());
    state = hub.beginSwitch(state);
    assert.ok(!hub.view(state, 'codex', true, now).accounts[1].canSwitch);
    const requested = JSON.stringify({schemaVersion: 1, provider: 'codex', outcome: 'requested', error: null,
        request: {requestId: 'r1', targetIdSuffix: '3c4d', targetEmail: target.email, requestedAt: '2030-01-01T00:09:30Z'}});
    state = hub.applySwitch(state, requested, 0, false, 'codex', target, now);
    assert.deepEqual([...hub.view(state, 'codex', true, now).notices], ['The hub is switching accounts…']);
    assert.ok(hub.view(state, 'codex', true, now).accounts.every(row => !row.canSwitch));
    const pending = resolution => response({pending: {requestId: 'r1', resolution, code: 'busy', reason: null}});
    assert.ok(read(state, pending('pending')).pending);
    const done = read(state, response({pending: {requestId: 'r1', resolution: 'done'},
        accounts: [account('1a2b'), account('3c4d', {active: true})]}));
    assert.deepEqual([...hub.view(done, 'codex', true, now).notices], ['The hub switched to a***3c4d@example.com (pro).']);
    assert.deepEqual([...hub.view(done, 'codex', false, now).notices], ['The hub switched to Account.']);
    const moved = read(done, response());
    assert.deepEqual([...hub.view(moved, 'codex', false, now).notices], ['The hub has since switched to Account 1.']);
    assert.deepEqual([...hub.view(read(state, pending('refused')), 'codex', false, now).notices],
        ['The hub refused the switch: busy']);
    assert.deepEqual([...hub.view(read(state, response({pending: {requestId: 'r1', resolution: 'failed'}})), 'codex',
        false, now).notices], ['The hub could not switch: No reason given']);
    const expiredText = 'The switch result is unknown. Refresh the hub before trying again.';
    assert.deepEqual([...hub.view(read(state, pending('expired')), 'codex', false, now).notices], [expiredText]);
    // Failing reads cannot hold a request open past the hub's acceptance window.
    const late = read(state, 'broken', 1, Date.parse('2030-01-01T00:21:00Z'));
    assert.deepEqual([late.pending, [...hub.view(late, 'codex', false, now).notices]], [null, [expiredText]]);
    const switched = hub.applySwitch(read(hub.initial(), response()), JSON.stringify({schemaVersion: 1, provider: 'codex',
        outcome: 'alreadyActive', request: null, error: null}), 0, false, 'codex', target, now);
    assert.deepEqual([...hub.view(switched, 'codex', false, now).notices], ['The hub switched to Account.']);
    const refused = hub.applySwitch(read(hub.initial(), response()), JSON.stringify({schemaVersion: 1, provider: 'codex',
        outcome: null, request: null, error: {code: 'notSwitchable', message: 'Not now'}}), 1, false, 'codex', target, now);
    assert.deepEqual([...hub.view(refused, 'codex', false, now).notices], ['The hub could not switch: Not now']);
});

test('usage arguments leave native Codex out only for multi-provider selections', () => {
    const base = {executable: 'codexbar', source: 'auto', showStatus: false};
    assert.ok(usage.command({...base, provider: 'both', excludeCodex: true}).includes('--exclude-provider'));
    assert.ok(usage.command({...base, provider: 'enabled', excludeCodex: true}).includes('--exclude-provider'));
    assert.ok(!usage.command({...base, provider: 'claude', excludeCodex: true}).includes('--exclude-provider'));
    assert.ok(!usage.command({...base, provider: 'both'}).includes('--exclude-provider'));
    assert.deepEqual([...usage.rows('[]', false, true)], []);
    assert.throws(() => usage.rows('[]', false));
});
