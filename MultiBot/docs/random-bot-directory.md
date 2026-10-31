# RandomBot browser

Open **MultiBot → Units → RandomBots**. This is an additional window; all existing roster modes remain.
It requires bridge capability `RANDOMBOT_DIRECTORY_V1` and server configuration
`MultiBotBridge.RandomBotDirectory.Enable = 1`.

Enter a name substring, choose class/faction/status/eligibility, and set a level range.
**My level ±5** fills the range and searches immediately. **Search / Refresh** applies the current filters
and returns to page 1. Filter changes otherwise take effect on the next explicit search.
Click Name, Level or Class to sort; clicking the same key reverses direction. Each server page has at most
25 rows. Select a row to see its invitation reason. **Invite** stays visible and is enabled for eligible selections.
While an invitation is pending it is disabled; after joining, select another row to invite the next bot
without searching again. The native WoW/Playerbots
invitation mechanism checks current rules again. No bots are created or logged in by this feature.

Online/group/master flags and zone come from live server state. V1 has no offline catalogue; the offline
filter explains this and returns no rows. Roles are explicitly unknown and have no misleading filter.
English class/race labels and English feature text are used. Native client error messages retain their
client language. Existing upstream translations and SavedVariables are preserved.

The window allocates only 25 reusable rows. No automatic directory polling occurs. Requests are limited
to one per 3 seconds and timeout after 12 seconds. Closing the window unregisters its events and cancels
its request logically; delayed replies/timer callbacks cannot repopulate it. Native invitations already
sent remain owned by WoW. Disconnect clears the pending request and capability flag.

On confirmed party/raid membership, the feature requests the existing bridge roster and leaves all roster
identity, duplicate handling and bot control to the normal MultiBot code.

Install the complete supplied `MultiBot` folder into `Interface/AddOns/MultiBot` with WoW closed.
Do not delete `WTF` or existing SavedVariables. A `/reload` is sufficient for subsequent source updates,
but close WoW for the first folder replacement so a backup can be made consistently.

Run the isolated Lua 5.1 regression test from this addon's root:

```sh
lua5.1 tests/random_bot_directory_test.lua
luac5.1 -p Core/MultiBotComm.lua Features/MultiBotRandomBotDirectory.lua \
  UI/MultiBotRandomBotDirectoryUI.lua UI/MultiBotUnitsRootUI.lua tests/random_bot_directory_test.lua
```

Tests fake native WoW APIs. They validate real capability/message dispatch and actual browser handlers,
including native invite calls, roster refresh and event/request cleanup, but cannot prove live in-game
acceptance or visual layout on every screen configuration.
