# Restless Soul / Egan's Blaster crash

## Confirmed cause

The operator reproduced the crash by using Egan's Blaster on a Restless Soul in Stratholme.
The debugger captured this faulting stack in the installed baseline:

```text
Object::GetUInt32Value
AutoBalance_AllCreatureScript::_isSummonCloneOfSummoner
AutoBalance_AllCreatureScript::ModifyCreatureAttributes
AutoBalance_AllCreatureScript::OnCreatureSelectLevel
ScriptMgr::OnCreatureSelectLevel
Creature::SelectLevel
Creature::UpdateEntry
SmartScript::ProcessAction
SmartAI::SpellHit
```

The soul's conversion to Freed Soul recalculates creature attributes. AutoBalance retained a raw pointer
to the original creature summoner, which can already have despawned. Clone detection subsequently
accessed that stale pointer. The ASan regression independently reproduces heap-use-after-free with the
old implementation when a summon outlives its summoner. The RandomBot browser is not on the crash path.

## Fix and evidence

AutoBalance now stores summoner GUID instead of a persistent Creature pointer and resolves the GUID in
the summon's map during clone detection. A missing summoner returns false safely. Cached summoner
name/level remain available for diagnostics. All uses of the removed pointer field were updated.
There are no creature-specific exceptions, quest/SQL changes, bot-permission changes or addon changes.

Base AutoBalance commit: `1d707cb`; fixed component commit: `23dd008`.
The complete module snapshot is in `fixes/mod-autobalance`; the patch is
`patches/autobalance-summoner-lifetime.patch`.

Validation:

- Actual worldserver Release build against the existing Playerbot core succeeded (`-j2`).
- Regression test compiles the actual clone-check function against fake native adapters with ASan/UBSan.
  Live/missing/despawned summoner, matching/nonmatching clone, excluded entry and nonsummon cases pass.
- The baseline test fails with heap-use-after-free in the same clone-check entry comparison.
- LeakSanitizer is disabled when running under the tool's tracing environment; address/undefined
  behavior sanitizers remain enabled.
- Module `git diff --check` passed. Full module codestyle checker reports 63 existing findings on both
  baseline and patched source; unrelated formatting was preserved.
- The source diff was reviewed at component commit `23dd008`, including all references to the replaced
  data field, same-map lookup lifetime, missing-GUID behavior and command diagnostics.
- Real in-game verification of the patched binary remains pending. The installed binary is unchanged.

```sh
ASAN_OPTIONS=detect_leaks=0 python3 fixes/mod-autobalance/tests/summoner_lifetime_test.py
```

The optional `--baseline` reproduction requires the original module checkout containing commit
`1d707cb`; run it there. The published snapshot has the fixed source but not the upstream Git history.

## Candidate and local deployment

Candidate: `dist/worldserver-autobalance-fix-linux-x86_64.gz`, a separate artifact from the original
RandomBot server candidate. Expected uncompressed SHA256:

```text
c5c77245b848c28061d49ce68734938b935093665c682e34a9f409f7f5900eff
```

For the current `acore` host, a prepared operator command installs the fix only when worldserver is
stopped, verifies the exact installed baseline and candidate hashes, creates a rollback backup, then
starts the unchanged diagnostic wrapper with the fixed binary:

```sh
sudo bash /home/karsten/restless-soul-investigation/install-fixed-worldserver.sh
```

Run only when ready to install the candidate. Authserver and configuration remain unchanged. The script
refuses to replace a running process. On initial startup failure, it restores the old binary. The
helper scripts are also preserved under `fixes/scripts`; they are host-specific and require the local
debugger preparation from this investigation. They are not run by CI.

After startup, repeat the quest, verify soul conversion and quest credit, and check other summoned
creatures still scale normally. Keep the debugger enabled for this confirmation. Once verified, the
server can be started normally using the existing startup script at an agreed restart.

For rollback, shut down a running worldserver gracefully first, restore the binary from the printed
`/home/karsten/acore-backups/autobalance-before-*` directory, then use the existing startup script.
No database or addon rollback is needed. Full raw crash logs stay in the private investigation directory;
they are not published because they contain player/runtime information.
