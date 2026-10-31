# Deployment and rollback

The production worldserver was not stopped, replaced or reconfigured during development. These are
manual deployment commands for a maintenance window after explicit operator approval. They are not
executed by tests, packaging, or CI. Authserver is unaffected.

## Verify the candidate

```sh
cd /home/karsten/acore_rndbot_invite
sha256sum -c dist/SHA256SUMS
mkdir -p /home/karsten/random-bot-release
gzip -dc dist/worldserver-linux-x86_64.gz > /home/karsten/random-bot-release/worldserver.to-install
chmod 0755 /home/karsten/random-bot-release/worldserver.to-install
ldd /home/karsten/random-bot-release/worldserver.to-install
```

No `not found` libraries may remain. The supplied binary was built as Release with `-j2` against the
exact core/modules in `versions.json`. If the installed stack has changed since that baseline, rebuild
against the current compatible stack and repeat validation. Full-server binary replacement affects the
entire worldserver, even though source changes are confined to the bridge.

Create a rollback backup **before** changing anything:

```sh
RANDOMBOT_BACKUP="/home/karsten/acore-backups/random-bot-before-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RANDOMBOT_BACKUP"
cp -p /usr/local/bin/worldserver "$RANDOMBOT_BACKUP/worldserver"
cp -p /usr/local/etc/modules/MultiBotBridge.conf "$RANDOMBOT_BACKUP/MultiBotBridge.conf"
printf '%s\n' "$RANDOMBOT_BACKUP"
```

Record the printed backup path. No schema/data migrations are introduced by this feature; retain your
normal database backups independently.

## Install only after approval

Run these commands manually only when ready to disconnect players and stop the worldserver:

```sh
tmux send-keys -t worldserver 'server shutdown 10' Enter
for RANDOMBOT_WAIT in $(seq 1 120); do
    pgrep -x worldserver >/dev/null || break
    sleep 1
done
if pgrep -x worldserver >/dev/null; then
    echo 'Worldserver still running; do not replace it.'
    exit 1
fi
sudo install -o root -g root -m 0755 /home/karsten/random-bot-release/worldserver.to-install \
    /usr/local/bin/worldserver.random-bot-new
sudo mv /usr/local/bin/worldserver.random-bot-new /usr/local/bin/worldserver
sudo sed -i '/^[[:space:]]*MultiBotBridge.RandomBotDirectory.Enable[[:space:]]*=/d' \
    /usr/local/etc/modules/MultiBotBridge.conf
printf '\nMultiBotBridge.RandomBotDirectory.Enable = 1\n' | \
    sudo tee -a /usr/local/etc/modules/MultiBotBridge.conf >/dev/null
tmux kill-session -t worldserver 2>/dev/null || true
tmux new-session -d -c / -s worldserver /usr/local/bin/worldserver
tmux capture-pane -p -t worldserver:0 -S -100
```

Check startup logs and client connection before declaring deployment complete. The query capability is
advertised even when the gate is off; a disabled server responds `DISABLED`. The gate can subsequently
be disabled and reloaded with the server's normal config reload operation without changing permissions.

## Windows addon

1. Close WoW. Back up `C:\Tools\World of Warcraft\Interface\AddOns\MultiBot`.
2. Extract `dist/MultiBot-RandomBotBrowser.zip` into `C:\Tools\World of Warcraft\Interface\AddOns`.
   The final TOC path must be `Interface\AddOns\MultiBot\MultiBot.toc`, not a nested duplicate folder.
3. Keep the entire `WTF` directory and its SavedVariables unchanged. No new persistent data is required.
4. Start WoW 3.3.5a, enable MultiBot, open Units → RandomBots.
5. Select Priest, levels 55–60, eligible, then sort by Level and choose a bot. Press Invite.
6. Confirm membership, appearance in the normal roster, Follow/Stay/Attack control and configured summon
   behavior. Also run the existing-feature checklist in `validation.md`.

The addon safely reports an unavailable capability against an old server. The old addon simply ignores
the extra capability on a new server; existing roster/control behavior remains on its original paths.

## Rollback

Set the browser gate to 0 to stop global directory access without removing the feature. For full rollback,
use the same graceful worldserver shutdown and process-exit check above. Then restore the recorded backup:

```sh
# Set this to the real recorded path, never leave the example placeholder.
RANDOMBOT_BACKUP=/home/karsten/acore-backups/random-bot-before-YOUR_TIMESTAMP
sudo install -o root -g root -m 0755 "$RANDOMBOT_BACKUP/worldserver" /usr/local/bin/worldserver.rollback-new
sudo mv /usr/local/bin/worldserver.rollback-new /usr/local/bin/worldserver
sudo cp -p "$RANDOMBOT_BACKUP/MultiBotBridge.conf" /usr/local/etc/modules/MultiBotBridge.conf
tmux kill-session -t worldserver 2>/dev/null || true
tmux new-session -d -c / -s worldserver /usr/local/bin/worldserver
```

With WoW closed, restore the backed-up MultiBot folder. SavedVariables remain valid. No feature database
rollback is necessary. Local source branches preserve baseline history; reverse the supplied patches only
on clean matching feature checkouts, or use isolated baseline worktrees. Do not hard-reset unrelated work.
