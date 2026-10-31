# Online RandomBot directory V1

The directory supplements `GET~ROSTER`; it never changes `GetBridgeVisibleBots()` or grants bot control.
Enable it explicitly in the installed `MultiBotBridge.conf`:

```ini
MultiBotBridge.RandomBotDirectory.Enable = 1
```

Capability: `RANDOMBOT_DIRECTORY_V1`. It is advertised through the existing chunked CAPS negotiation,
even when the administrator has disabled queries (queries then return `DISABLED`).

## Wire protocol

Existing `MBOT` transport, protocol version 1, percent-encoded string fields, `~` separators.
All directory responses are private WHISPER responses to the authenticated requester, including errors.
The existing 255-byte wire limit includes `MBOT\t`. Each response row is a separate packet.

```text
GET~RANDOMBOT_DIRECTORY~token~name~class~minLevel~maxLevel~faction~status~invite~page~sort~descending~ANY
RBD_BEGIN~token~page~total~count~ONLINE_ONLY
RBD_ENTRY~token~guid~name~class~level~race~faction~UNKNOWN~ONLINE~zoneId~grouped~controlled~reason~zoneName
RBD_END~token~page~total~count~ONLINE_ONLY
ERR~GET~RANDOMBOT_DIRECTORY~token~reason
```

- Token: existing bridge token rules, maximum 64 bytes. UI generates unique tokens per session/request.
- Name: percent-encoded substring, at most 48 decoded bytes; ASCII case-insensitive matching.
- Class: 0=any, otherwise WoW class ID 1–9 or 11.
- Level bounds: 1–80, minimum must not exceed maximum.
- Faction: 0=any, 1=Alliance, 2=Horde.
- Status: 0=all available, 1=online, 2=offline. V1 contains online entries only; offline queries are explicitly empty.
- Invite: 0=any, 1=preflight eligible, 2=ineligible.
- Page: zero-based, maximum 100000. Fixed page size 25; no caller-controlled result limit.
- Sort: NAME, LEVEL or CLASS. Descending: 0 or 1. Name and GUID provide deterministic tie breaks.
- Final ANY: reserved role filter; other values are rejected because role is not reliably known.
- Total: matching online entries before pagination. Count: rows in this page, maximum 25.
- Grouped/controlled: 0 or 1; controlled means mastered by this requester, not merely any master.
- Zone ID: current server zone; optional English zone name is omitted if its encoding exceeds the packet budget.
- UNKNOWN is the role; ONLINE is derived from `IsInWorld()`, not a database online flag.
- The client commits a page only when BEGIN/END match and the exact number of unique rows arrived.
  Responses with old tokens, different connection generations or unexpected senders are ignored/rejected.

Typical reasons: OK, OTHER_GROUP, IN_YOUR_GROUP, GROUP_FULL, NOT_LEADER, WRONG_FACTION,
PERMISSION_DENIED, LOW_LEVEL, GEARSCORE, BATTLEGROUND, BG_QUEUE, PENDING_INVITE, BUSY.
Protocol errors also include DISABLED, BAD_FIELD_COUNT, BAD_TOKEN, BAD_FILTER, NO_SESSION,
RATE_LIMIT, TOKEN_USED and TOO_LARGE. Existing bridge framing rejects oversized incoming messages first.

## Runtime and security

Chat handlers strictly validate fields and queue value data (GUID/account/token/query), never persistent
Player pointers. The queue contains at most 16 queries. A WorldScript processes at most one query every
500 ms, after the local core's MapMgr worker wait. This avoids dereferencing map-owned players while
map updates are running. No database queries, login scans, per-frame bot scans or automatic refresh loops
are added. At most 512 rate states are retained; each requester may issue one query every 3 seconds.
Accepted tokens are protected against replay for 60 seconds. Expired requester state is pruned on queries.

The authenticated live player is resolved again before processing, with an account check. Only online
players that the native RandomPlayerbotMgr identifies as random bots and that have bot AI are included.
Cheap filters precede security evaluation. Selection/sorting runs on value rows. The global enable switch
is cached at configuration load/reload.

Preflight uses the native PlayerbotSecurity INVITE level, current groups, faction rules, pending invites,
battleground and teleport state. It is advisory: core script hooks, trial restrictions, ignore lists,
instance constraints and changes after the snapshot are finally checked by the native invitation path.
No directory RUN command, GM command, master mutation, group mutation, login or teleport command exists.

The addon calls `InviteUnit(name)` from a button click outside combat. Core `HandleGroupInviteOpcode` and
Playerbots `AcceptInvitationAction` retain all final authorization and acceptance logic. That existing action
sets master/follow and applies configured summon behavior. Once the UI observes membership, it requests
normal `GET~ROSTER`. It never inserts directory rows into the normal roster. Native localized group errors
are shown while an invite is pending. After 20 seconds without confirmed membership, the UI reports that
no join was confirmed; it does not claim the server has revoked or expired the invitation.

## Offline and role limits

No offline catalogue or offline invitations are implemented in V1. Database feasibility was checked:
`characters` has the identity/account/class/race/level fields, and PlayerbotAIConfig exposes RandomBotAccounts.
CharacterCache supports individual lookups, but not public enumeration. The existing prepared
CHAR_SEL_CHARS_BY_ACCOUNT_ID selects GUIDs only and is registered SYNCH. A complete catalogue should
use a separately prepared asynchronous query and bounded cached snapshots for configured random accounts,
excluding deleted characters. It must reconcile online state from live server objects; `characters.online`
is not authoritative. No schema or additional database is needed. Do not reuse the synchronous alt-roster
query for global catalogue searches.

Roles remain UNKNOWN. Class or talent labels alone do not prove the active tank/healer/DPS role; even
some native class strategy type labels differ from the role implied by their names. No role is invented.

## Validation

`tests/random_bot_directory_test.cpp` compiles the actual directory implementation against fake native
adapters. It covers 2500 online bots, first/next pages, empty/offline responses, combined filters, all sort
keys/directions, invalid/oversized fields, replay/rate/queue limits, permissions, group/faction/battleground
preflight and account changes while queued. The 100 x 2500 load benchmark measures value filtering/sorting,
not native security evaluation or live-server CPU impact.

Build the real worldserver against the pinned Playerbot core to validate native API compatibility.
No live in-game acceptance or full existing-feature regression is claimed by these isolated tests.
