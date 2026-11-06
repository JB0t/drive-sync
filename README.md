# drive-sync

Two-way Google Drive sync for Linux. Google does not ship a Drive client for Linux. `drive-sync` fills that gap with a small wrapper around [`rclone bisync`](https://rclone.org/bisync/).

- **Two-way.** Additions, edits and deletions on either side are copied to the other side.
- **Newest wins.** If a file changed on both sides between runs, the copy with the newer modification time wins. The older copy is kept as `name.conflict1`, `name.conflict2`, and so on, so no change is silently lost.
- **Runs on a timer.** A systemd user timer runs the sync every 5 minutes by default.
- **Safe defaults.**
  - rclone's safety checks are kept: a run aborts if too many files would be deleted or changed.
  - Each sync pair has a lock, so runs never overlap.
  - Default filters keep secrets, `.git`, and large build and Terraform artefacts out of Drive.

## Install

```bash
git clone https://github.com/JB0t/drive-sync.git ~/git/JB0t/drive-sync
cd ~/git/JB0t/drive-sync
./install.sh
```

`install.sh` does three things. It does not need sudo.

- If rclone is missing or older than 1.66, it installs the current rclone release into `~/.local/bin`. The download is checked against the official `SHA256SUMS`.
- It links `drive-sync` into `~/.local/bin`.
- It creates `~/.config/drive-sync/` and puts `default.filters` in it.

Next, connect your Google account.

**First, create your own OAuth client.** rclone's shared Google client ID is being retired during 2026, so you need your own. It is free and takes about five minutes:

1. In the [Google Cloud console](https://console.cloud.google.com/), create a project.
2. Go to **APIs & Services → Library** and enable the **Google Drive API**.
3. Set up the **OAuth consent screen** (Google Auth Platform):
   - Choose the **External** audience, and give the app any name.
   - **Publish** the app. While an app is in *Testing* status, its refresh tokens expire after 7 days.
4. Go to **Clients → Create client** and choose the **Desktop app** type. Note the client ID and the client secret.

Then run the following in a normal terminal. It opens a browser for sign-in:

```bash
rclone config create gdrive drive scope=drive client_id=YOUR_ID client_secret=YOUR_SECRET
```

Google warns that the app is unverified. This is expected, because it is your own app: click **Advanced → Go to (app name)**. On the permissions screen, tick the Drive permission box.

Use `scope=drive`. With the narrower `drive.file` scope, rclone can only see files that rclone uploaded itself. Anything you add through the Drive web UI or another device would then never sync back down.

## Use

```bash
# Register a pair. The first run merges both sides (newer copy wins, nothing is deleted).
drive-sync add role-deep-dives ~/role-deep-dives gdrive:role-deep-dives

# Sync automatically every 5 minutes
drive-sync install-timer 5min

drive-sync status              # last result for each pair, and the next timer run
drive-sync sync                # sync all pairs now
drive-sync sync role-deep-dives
drive-sync dry-run role-deep-dives
drive-sync log role-deep-dives 100
drive-sync list
drive-sync remove role-deep-dives   # unregisters the pair; no files are touched
drive-sync uninstall-timer
```

A pair can use its own filters file instead of the default:

```bash
drive-sync add notes ~/notes gdrive:notes ~/notes/.drive-sync.filters
```

## When a sync fails

`drive-sync status` shows `FAILED` for the pair. If `notify-send` is installed, you also get a desktop notification. The failure message tells you what to do next:

| Message | Meaning | What to do |
|---|---|---|
| `safety abort` | More files would change or be deleted than rclone allows (`--max-delete` defaults to 50%). This also happens when *every* file in a small folder changed | Check what changed with `drive-sync dry-run NAME` or `drive-sync log NAME`. If the changes are expected, run `drive-sync sync NAME --force` |
| `rclone asks for a resync` | The saved sync state no longer matches the files, for example after a crash or a filters change | Run `drive-sync resync NAME`. It merges both sides (newer copy wins) and never deletes anything. A file you deleted on one side may come back |

You must run `drive-sync resync NAME` after editing a pair's filters file. rclone stores a hash of the filters and refuses to run while they differ.

## How it works

Each pair is one line in `~/.config/drive-sync/pairs.conf`:

```
name|/abs/local/path|remote:path|/optional/filters/file
```

Every run calls rclone with these flags:

```
rclone bisync LOCAL REMOTE \
  --conflict-resolve newer --conflict-loser num \
  --resilient --recover --max-lock 2m \
  --create-empty-src-dirs --drive-skip-gdocs \
  --compare size,modtime --track-renames \
  --filters-file FILTERS
```

| Path | Contents |
|---|---|
| `~/.local/state/drive-sync/NAME.log` | Logs |
| `~/.local/state/drive-sync/NAME.status` | Last result |
| `~/.local/state/drive-sync/NAME.lock` | Lock file |
| `~/.cache/rclone/bisync/` | rclone's saved listings, which it uses to detect changes |

## Limitations

- **Polling, not live.** Changes sync on the next timer run, not the moment you save.
- **Native Google Docs, Sheets and Slides are skipped.** Drive reports no file size for them, so they cannot be compared. Ordinary files such as `.docx` and `.md` sync normally.
- **Modification times decide conflicts.** Keep clocks synced with NTP or chrony.

## Testing locally without Drive

```bash
export XDG_CONFIG_HOME=/tmp/ds/cfg XDG_STATE_HOME=/tmp/ds/state RCLONE_CONFIG_FAKE_TYPE=local
mkdir -p /tmp/ds/{a,b,cfg/drive-sync} && cp share/default.filters /tmp/ds/cfg/drive-sync/
bin/drive-sync add t /tmp/ds/a fake:/tmp/ds/b
```
