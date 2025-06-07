# juvy Technical Notes

## How juvy Currently Works

### Configuration Structure

**Config Files:**
- `$HOME/.config/juvy/config` - Stores settings (currently just `JUVY_BACKUP_DIR`)
- `$HOME/.config/juvy/backup` - List of files to backup (one path per line)

**Default Setup:**
- Backup directory: `$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy` (iCloud)
- Initial backup list: `/.zshrc` and `/.gitconfig` (relative to $HOME)

### Operational Flow

1. **Initialization (`juvy init`):**
   - Creates config directory at `$HOME/.config/juvy/`
   - Creates backup list with default files (`.zshrc` and `.gitconfig`)
   - Prompts for backup location (or uses iCloud default)
   - Initializes a git repo in the backup directory

2. **Backup Process (`juvy backup`):**
   - Uses rsync with `--files-from` to copy files listed in `$HOME/.config/juvy/backup`
   - Source: `$HOME`
   - Destination: `$JUVY_BACKUP_DIR`
   - If changes detected (via `git status --porcelain`), commits with timestamp

3. **File Storage Structure:**
   ```
   $JUVY_BACKUP_DIR/
   ├── .git/
   ├── .zshrc
   └── .gitconfig
   ```
   Files maintain their relative paths from $HOME

### Example Flow
```bash
# After init, your backup list has:
/.zshrc
/.gitconfig

# Running backup executes:
rsync -a --files-from="$HOME/.config/juvy/backup" "$HOME" "$JUVY_BACKUP_DIR"
# This copies $HOME/.zshrc → $JUVY_BACKUP_DIR/.zshrc
# And $HOME/.gitconfig → $JUVY_BACKUP_DIR/.gitconfig

# Git commit with message: "Backup: 2024-01-06 14:30:45"
```

## Performance Analysis

### Current Efficiency
- `rsync -a` is efficient - only copies changed files
- Git commits only when changes exist (good use of `--porcelain`)
- No unnecessary file scanning or processing
- Simple file list reading

### Potential Issues at Scale

1. **Large Binary Files:**
   - Git stores full copies of binaries in history
   - Risk if backing up `~/.vim/bundle/` or `~/.vscode/extensions/`
   - Solution: Add `.gitignore` patterns or size warnings

2. **Many Small Files:**
   - rsync handles this well
   - Git can slow down with thousands of files
   - Dotfiles typically don't hit this limit

3. **Symlink Handling:**
   - `rsync -a` copies symlinks as symlinks (correct behavior)
   - Restore might break if symlink target doesn't exist

### Minor Optimization Opportunities

1. **Batch Git Operations:**
   ```bash
   # Current: individual git commands
   git -C $JUVY_BACKUP_DIR add .
   git -C $JUVY_BACKUP_DIR commit -m "..."
   
   # Could be: single git call
   git -C $JUVY_BACKUP_DIR add . && git -C $JUVY_BACKUP_DIR commit -m "..."
   ```

2. **Incremental Backup List:**
   - Currently re-reads entire file list each time
   - For hundreds of files, could cache/check modifications
   - Not worth the complexity for typical use

### Performance Verdict
For typical dotfile use cases (<100 files, mostly text), the current approach is appropriately simple and efficient. The code clarity and simplicity outweigh any micro-optimizations. The only real concern is preventing users from accidentally backing up large directories.

## Key Design Decisions

1. **rsync over cp:** Efficient incremental copies
2. **Git for versioning:** Provides history without implementing versioning
3. **Simple text files for config:** Easy to edit and debug
4. **No daemon/scheduling:** User controls when backups happen
5. **Relative paths from $HOME:** Maintains directory structure