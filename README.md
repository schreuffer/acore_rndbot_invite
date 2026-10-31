# AzerothCore RandomBot browser for MultiBot Chatless

An integrated **MultiBot → Units → RandomBots** browser for existing online RandomBots on WoW 3.3.5a.
Search names, combine class/level/faction/online/eligibility filters, sort by name/level/class in either
direction, browse 25-row server pages, select a bot and use the native **Invite** action.

No new accounts, characters, database or group system. Existing MultiBot rosters and bot controls remain
in place. The new feature, code comments and documentation are English; upstream translations are retained.

**Status:** real Playerbot-core worldserver build passed, isolated server and Lua 5.1 tests passed.
The server candidate has been deployed by the operator and native bot invitation has been confirmed
in-game. The latest addon UI fixes still require visual verification in the Windows client; broader
existing-feature regression acceptance remains open. V1 contains online bots only; offline catalogue/login and
reliable role classification are not implemented. Unknown roles are explicitly marked.

## Downloads and layout

- [Complete addon ZIP](dist/MultiBot-RandomBotBrowser.zip): extract to obtain `MultiBot/`.
- [Built Linux worldserver](dist/worldserver-linux-x86_64.gz): test candidate for the existing `acore` stack.
- [Checksums](dist/SHA256SUMS), [component versions](versions.json), [validation report](docs/validation.md).
- `MultiBot/`: complete updated addon source and upstream assets, including the upstream GPLv3 license.
- `mod-multibot-bridge/`: complete updated bridge source, configuration template, tests and protocol documentation.
- `patches/`: exact changes against bridge `9f0e8ba` and addon `020210ba`, including new files.
- [Deployment and rollback](docs/deployment.md), [wire protocol and architecture](mod-multibot-bridge/docs/random-bot-directory.md),
  [browser instructions](MultiBot/docs/random-bot-directory.md).

The full server binary is supplied compressed because the bridge is statically linked into this core;
there is no separate bridge `.so` to install. Authserver does not need replacement. The candidate includes
the existing server's other modules and must be used only with the pinned compatible stack. Rebuild if
core or module versions differ.

## Pinned components

| Component | Baseline | Tested feature commit |
| --- | --- | --- |
| AzerothCore Playerbot | `93333d6a9` | unchanged |
| mod-playerbots | `05a1f6fc` | unchanged |
| mod-multibot-bridge | `9f0e8ba` | `518da78` |
| MultiBot Chatless | `020210ba` | `885619c` |
| mod-questie-bridge | `9a24fd65` | unchanged |

Full hashes are in `versions.json`. Component feature commits are local commits in their respective
source repositories; the snapshots and patches here contain their exact content. This repository's own
commit identifies the published combined release. Upstream authorship and license notices are retained.
Only the new integration and tests were added for this project; no upstream repository was pushed to.

## Architecture

Capability `RANDOMBOT_DIRECTORY_V1` adds a separate GET query and private framed responses. An opt-in
configuration gate, strict validation, bounded queue, rate limit and replay protection guard the query.
The WorldScript scans live players only on request, after map workers finish; it filters/sorts values
before returning at most 25 rows. No database calls are added. Normal `GET~ROSTER` and
`GetBridgeVisibleBots()` are unchanged.

Eligibility is a preflight using native Playerbots security and current state. `InviteUnit()` performs
the actual native invitation; existing acceptance code sets master, follow and configured summoning.
The browser requests the normal roster after confirmed group membership. It never creates competing
roster entries or mutates bot control itself.

## Tests and packaging

On a development Linux host with a C++20 compiler, Python 3 and Lua 5.1:

```sh
./scripts/test.sh
python3 scripts/package-addon.py
```

The tests compile the actual directory implementation with fake native dependencies and exercise the
real addon communication/UI handlers with fake WoW APIs. They include a 2500-bot load sample.
See [validation](docs/validation.md) for what is and is not proven.

Build against the existing pinned core (do not run `make install` during development):

```sh
cd /home/karsten/azerothcore-wotlk/modules/mod-multibot-bridge
git apply --check /home/karsten/acore_rndbot_invite/patches/mod-multibot-bridge.patch
git apply /home/karsten/acore_rndbot_invite/patches/mod-multibot-bridge.patch
cmake --build /home/karsten/azerothcore-wotlk/build --target worldserver -j2
```

Apply only to a clean baseline checkout. The development workspace already contains the feature; do
not apply its patch again there. For a fresh stack, configure the normal Playerbot-core CMake tree first.

## Stratholme Restless Soul crash fix

A separate AutoBalance lifetime fix and server candidate are documented in
[Restless Soul crash investigation](docs/restless-soul-crash.md). This addresses the captured
server crash when using Egan's Blaster; it does not require an addon update.
