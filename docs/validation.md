# Validation and remaining acceptance

## Completed

- Actual local repositories inspected before implementation; reference commits matched.
- Native `HandleGroupInviteOpcode` and Playerbots `AcceptInvitationAction` inspected. Acceptance already
  checks `PLAYERBOT_SECURITY_INVITE`, sets the random bot's master, resets strategies, enables follow and
  performs configured group summoning. The implementation uses that path via `InviteUnit`.
- Real `cmake --build ... --target worldserver -j2` succeeded in the existing Playerbot-core build tree.
  No installation command or runtime server command was executed.
- C++20 server tests compiled with `-Wall -Wextra -Werror` and passed. The actual directory `.inc` is
  included with fake native adapters, not a rewritten implementation.
- Lua 5.1 syntax checks passed on every modified Lua file, including the existing large communication
  dispatcher. The host had liblua5.1 and headers but no Lua CLI. A small local CLI wrapper used
  `luaL_loadfile` for syntax and the real Lua 5.1 VM for execution. Its source is included under
  `validation/lua51-run.c`; normal `lua5.1`/`luac5.1` can run the same checks and CI uses those binaries.
- Lua tests passed through real capability and message dispatch, expected-sender validation and actual
  browser handlers, with fake native UI/network/group APIs.
- `git diff --check` passed for both component changes.
- Core C++ codestyle checker passed on the new implementation files. The full existing bridge source
  has 55 pre-existing multiple-blank-line findings; its baseline has the same 55 findings. These unrelated
  lines were preserved. clang-format was not installed in this environment.
- Installed production worldserver SHA256 still matched the pre-feature build at final verification.

## Test matrix

| Requirement | Evidence | Limit |
| --- | --- | --- |
| Capability negotiation | Real addon CAPS dispatch test; bridge compiles capability chunking | No live handshake yet |
| First and next page | Real server directory test, 2500 faked online players; Lua atomic framing | Native dependencies faked |
| Combined filters | Name/class/55–60/faction/eligibility/status assertions | ASCII name case folding |
| Ascending/descending sort | All NAME/LEVEL/CLASS orders checked with deterministic reverse order | No database involved |
| Empty/offline results | Server and Lua tests, explicitly ONLINE_ONLY | Offline catalogue intentionally absent |
| Malformed/oversized input | Real queue handler field bounds, class/level/size validation; Lua bad frames/duplicates/encoding | Existing envelope size guard reused |
| Rate/replay/work limits | Same-token replay, 3 s throttle, queue cap 16, global 500 ms processing | Live flood/CPU profiling not performed |
| Eligibility/errors | Group/full/leader/faction/security/level/BG assertions; native errors shown by real UI handler | Native final invitation remains authoritative |
| Invite/normal roster | Real UI calls fake InviteUnit, observes fake group membership and sends real GET~ROSTER | Actual bot acceptance not verified in-game |
| Close/disconnect/timeouts | Pending request canceled, events removed, old response ignored, capability reset | Native client lifetime not available |
| Load sample | 100 filtering/sorting runs of 2500 rows: about 79 ms on this host | Excludes live security and map/update work |
| Existing functions | Roster and controls left unchanged; separate directory state; original dispatch retained | Full functional regression below still open |

## Required live acceptance

Run on the pinned stack after an approved deployment:

1. Verify a known online random bot can receive a normal `/invite Name` under current Playerbots settings.
2. Open Units → RandomBots. Query an unfiltered page, page forward/back, refresh, try an empty search.
3. Combine Priest + levels 55–60 + eligible and toggle each sort direction. Check faction/status filters
   and My level ±5. Compare online, group and zone data against server state.
4. Invite a permitted online bot. Confirm native acceptance, master/follow and configured teleport behavior.
   Confirm exactly one entry appears in the normal MultiBot roster and normal control works.
5. Test another-group, incompatible-faction, full-group, permission-denied, BG and stale/offline targets.
   Check native error text and refresh results. Unknown data must remain unknown.
6. Close/reopen while a request is pending. Reload UI and disconnect with a pending request. Check Lua
   errors, event cleanup and capability reset. Repeat at the actual Windows client screen/UI scale.
7. Smoke-test normal/alt/guild rosters, friends/favorites, Creator/AddClass, lifecycle, Follow/Stay/Attack,
   strategies, inventory, quests and party/raid management. No full-regression success is claimed yet.
8. Compare server update time/CPU before and during normal manual searches with the real bot pool.
   Synthetic sorting timing alone is not a live performance acceptance result.

## Changed component files

Bridge: `README.md`, `conf/MultiBotBridge.conf.dist`, `src/MultiBotBridge.cpp`,
`src/RandomBotDirectory.h`, `src/RandomBotDirectory.inc`, `tests/random_bot_directory_test.cpp`,
`docs/random-bot-directory.md`.

Addon: `README.md`, `MultiBot.toc`, `Core/MultiBotComm.lua`, `UI/MultiBotUnitsRootUI.lua`,
`Features/MultiBotRandomBotDirectory.lua`, `UI/MultiBotRandomBotDirectoryUI.lua`,
`tests/random_bot_directory_test.lua`, `docs/random-bot-directory.md`.

No core or mod-playerbots source, SQL, live configuration, accounts or Windows installation was changed.
