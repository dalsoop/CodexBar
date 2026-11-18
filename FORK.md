# dalsoop/CodexBar fork (`gujo`)

This is a long-lived, self-managed fork of [steipete/CodexBar](https://github.com/steipete/CodexBar). It is built and shipped as `net.ranode.codexbar` with its own Sparkle feed, separately from the official app (`com.steipete.codexbar`). Upstream closed the pull request for the fork's feature (steipete/CodexBar#4630, 2026-10-19), so the fork keeps it on its own and does not wait for upstream acceptance.

## Upstream is read-only

- Never write to steipete/CodexBar in any way: no pull requests (do not reopen or edit #4630), no issues, no comments, no reactions, no pushes, and no "Sync fork" or "Contribute" buttons that open pull requests.
- Only read from upstream: `git fetch`, releases and tags.
- Pushes go only to this fork (`dalsoop/CodexBar`) and to the owner's private GitLab repositories. The local `upstream` remote has its push URL disabled.

## Branches

- `gujo` is the only long-lived branch and the release branch. It holds upstream's release history plus the fork's own commits: the opencodex hub account feature (`feat(…)`, `fix(…)`, `test(…)`, `docs(…)`) and the redistribution settings (`build:` commits that let a redistributor set the bundle ID, feed, Sparkle key and build number).
- `gujo` changes only through reviewed pull requests on this fork, merged with merge commits (`gh pr merge --merge`), never squashed, rebased or force-pushed.
- A new upstream release comes in through its own pull request that merges the release tag (for example `v0.84.0`) into a branch from `gujo`. Conflicts are resolved in that merge commit: the fork's hub features win, and upstream's side is taken for every other conflict. The pull request lists each conflict resolution and any upstream change left out.
- The former pull request branch `feat/opencodex-hub-accounts` is archived as the tag `archive/opencodex-hub-accounts-pr4630` and deleted. Do not recreate it.

## Fork-only features

- Per-account quota meters and responsive rows in the merged provider switcher
  (`docs/provider-switcher-accounts.md`).

- Configurable public Codex reset news in Settings → Providers → Codex and the Codex menu
  (`docs/reset-announcements.md`).
- opencodex hub accounts for Claude, Codex and Grok (`docs/configuration.md`, "opencodex hub snapshot").
- The app state mirror `~/.swift-app-state/codexbar.json` and `codexbar app-state [--json]` (`docs/app-state.md`), so scripts and agents can see what the menu shows.

## Release

Releases are built, signed, notarised, published and installed by the fork-sync tool in the private `upstream-mono` repository (`tools/codexbar-fork-sync/`), so this branch carries no fleet configuration. After an upstream-release pull request or another fork change is merged, `sync.sh release <full SHA of origin/gujo>` ships that reviewed head: it gates it on m5m2 (build, the fork's focused tests, `make check` and the locale check), then signs, notarises and publishes on m5m1 and installs on the Macs that pass a preflight. On a red gate it stops and leaves the published release as it is.

The tool's weekly `sync.sh run` still rebases `gujo` onto an upstream release tag that `gujo` does not contain yet and force-pushes it. That path does not match the merge-commit history above, so a new upstream release is merged by pull request first; once the tag is in `gujo`, `run` and `release` gate and publish the head without rebasing.

The build number is upstream's `BUILD_NUMBER` × 100 + the fork's revision for that upstream build (upstream 171 → 17101, 17102, …), so a fork build always sorts above the upstream build it follows.
