# Upstream account-management reuse audit

## Compared implementations

The October 21 review compared OpenCodex upstream stable v2.89.0, commit `dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109`, with the installed personal release `2.89.1-dalsoop.1`, commit `0f889a24c093d898d85042bdefa44e772bbfb6ce`. The installed copies of `src/cli/account.ts`, `src/cli/account-api.ts`, `src/link/management-routes.ts`, `src/server/management/oauth-account-routes.ts` and `src/oauth/anthropic-routing.ts` have exactly the same SHA-256 hashes as upstream v2.89.0. The earlier v2.88.0 observations were therefore checked against the actual current installation rather than assumed current.

CodexBar upstream was inspected at `489aad74fbd55a22db570c025b6d57aac654cd5a`. It provides the external Claude account adapter and the shared multi-account layout planner, which the fork reuses. The OpenCodex hub reader, snapshot and request-file integration are additions in this fork.

## Native capabilities and fork responsibility

| Concern | Existing upstream behavior | Fork action |
| --- | --- | --- |
| Account membership | `ocx account list <provider> --json` reads the Home over the connection-bound Remote Link relay. It is a live read of the Home's stored membership, independent of our SSH snapshot-delivery job. | Keep using the native CLI. A successful passive list check must not tell the user to wait for our snapshot job. |
| Quota per account | `--quota` opts into per-credential upstream work. Remote Link rejects the quota query. The plain OAuth-account response omits quota. | Keep missing quota missing, or explicitly retain dated last-known observations. Do not add another probe or bypass the relay. |
| Provider quota summary | `ocx provider quota --json` reads `/api/provider-quotas`; the response contains provider reports, with no account id binding for assigning each report to an individual account card. | Do not copy a provider summary into every account. It cannot replace the per-account snapshot contract. |
| Automatic account selection and retry | OpenCodex owns quota-based selection, affinity, eligibility, cooldowns and the per-request failover/send limits. | No independent router, ten-account limit or retry ladder was introduced in CodexBar. Retain native behavior. |
| Remote account changes | The link allowlist accepts GET/HEAD reads and explicitly refuses changes. The Home's authenticated management UI owns account addition, reauthentication and selection. | The existing browser handoff reuses that UI. Our request-file/SSH mechanism is an extra remote-control workflow, not an upstream feature. Removing it changes menu-bar direct-switch behavior and must also account for mac-infra consumers. |
| Management browser address | A Remote Link connection reports the data tunnel as its management URL. The tunnel does not serve the management UI. GUI pairing creates a separate short-lived secret capability. | Keep the explicit HTTPS management origin and normal browser authentication. Do not collect pairing grants or manufacture a management relay. |

The snapshot/request machinery also carries quota observations, switchability and request outcomes. It cannot be deleted wholesale merely because native membership reads exist. The reader currently retains a fresh snapshot for those established capabilities and uses the native passive list when the snapshot is absent or stale. Switching the entire remote workflow to the native management website is a separate user-facing choice.

## Corrected duplicate dependency

The app treated every successful native linked-list result as waiting for snapshot sync. This conflated read-only authority with stale data and contradicted the native read that had just succeeded. The completion state now depends on actual snapshot staleness. A successful linked list reports that membership was checked, while retaining read-only authority, unknown quota freshness and the instruction that opening a browser does not establish sign-in success. An old fallback snapshot still reports that sync is needed.

The regression supplies three native linked accounts with no quota and no writable snapshot. It requires one successful check, three retained accounts, no attention/sync-wait state, no local switching permission, no invented source timestamp and no OAuth-success claim. Existing stale-snapshot and unavailable-source regressions remain required.

## Source evidence

- [Native account read and Remote Link classification](https://github.com/lidge-jun/opencodex/blob/dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109/src/cli/account-api.ts)
- [Remote Link allowlist and explicit write refusal](https://github.com/lidge-jun/opencodex/blob/dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109/src/link/management-routes.ts)
- [OAuth membership and opt-in per-account quota](https://github.com/lidge-jun/opencodex/blob/dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109/src/server/management/oauth-account-routes.ts#L481)
- [Native provider quota command](https://github.com/lidge-jun/opencodex/blob/dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109/src/cli/provider-runtime.ts#L243)
- [Provider quota response shape](https://github.com/lidge-jun/opencodex/blob/dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109/src/providers/quota/report-cache.ts#L52)
- [Native Claude account selection and failover](https://github.com/lidge-jun/opencodex/blob/dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109/src/oauth/anthropic-routing.ts)
- [GUI pairing capability lifecycle](https://github.com/lidge-jun/opencodex/blob/dd2bdd2fe3ff6fc2d75019c8b7dc201b835b4109/src/cli/gui.ts)
- [CodexBar upstream external account reader](https://github.com/steipete/CodexBar/blob/489aad74fbd55a22db570c025b6d57aac654cd5a/Sources/CodexBarCore/Providers/Claude/ClaudeSwap/ClaudeSwapAccountReader.swift)

## Verification

m5m2 Build Pipeline job `B40CAD21-8F67-4F60-A4CC-78798C5A43FC` passed 88 focused tests (36 application Swift Testing, 43 shared Swift Testing and nine XCTest tests), including the native-read regression and the existing 12/20/50-account coverage. `make check` passed with zero SwiftLint violations in 3,112 files. No native routing policy, link write permission, quota probe or authentication flow changed. The current remote direct-switch workflow is retained while its interaction choice remains separate.
