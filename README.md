# things3-org-backup

Export Things3 to a single `things3.org` for beorg / Emacs / Orgzly.

## Install

```bash
bash install.sh           # daily at 09:00
bash install.sh 21 30     # daily at 21:30
```

## Uninstall

```bash
bash uninstall.sh
bash uninstall.sh --purge-backups
```

## Script config

Edit top of `things3-backup.applescript`:

```applescript
set MAX_BACKUPS       to 10
set INCLUDE_COMPLETED to true
set BACKUP_ROOT to "/Users/" & USERNAME & "/Documents/Things3-Backups"
```

## Requirements

macOS 12+, Things3, beorg / Emacs / Orgzly

## License

MIT
