# juvy Planning Document

## Project Vision
Transform juvy from a personal script into a simple but reliable dotfile backup tool that others can use on macOS with zsh.

## Current State Analysis

### Strengths
- Minimal and focused - does one thing
- No dependencies, pure zsh
- Git integration for versioning
- Simple rsync approach
- Clean function namespace with `_juvy_` prefix
- Good use of `emulate -L zsh` for consistency

### Weaknesses
- **No restore functionality** - Critical missing feature
- **Poor error handling** - Commands assume success, rsync could fail silently
- **Platform-specific** - Hardcoded macOS/zsh paths with iCloud
- **No validation** - Doesn't check if backup paths exist
- **Limited features** - No dry-run, diff preview, or selective operations
- **Fragile path handling** - Escaped spaces could break
- **Installation assumes** - Specific directory structure (`$HOME/repos/juvy/`)

## Installation Strategy

### Current Method
```bash
source $HOME/repos/juvy/juvy.zsh
```

### Proposed Installation Options

1. **Single-file install via curl** (Recommended)
```bash
curl -sSL https://raw.githubusercontent.com/user/juvy/main/juvy.zsh -o ~/.juvy.zsh
echo 'source ~/.juvy.zsh' >> ~/.zshrc
```

2. **Self-contained installer**
- Add `juvy install` command that copies itself to standard location
- Auto-adds source line to .zshrc

3. **Homebrew tap** (Future, when stable)
```bash
brew tap user/juvy
brew install juvy
```

## Feature Priority List

### High Priority
1. **Restore functionality** - Recover backed up files to original locations
2. **Error handling** - Validate operations and provide clear error messages
3. **Path validation** - Check files exist before backup

### Medium Priority
4. **Diff/preview command** - Show what changed before backup
5. **Add/remove commands** - Modify tracked files list
6. **Dry-run option** - Preview what backup would do

### Low Priority
7. **Help system** - Built-in usage documentation
8. **Platform flexibility** - Support different cloud storage providers
9. **List command** - Show currently tracked files
10. **Version info** - Track juvy version for updates

## Implementation Details

### Restore Feature Design
- `juvy restore` - Restore all files from latest backup
- `juvy restore <file>` - Restore specific file
- `juvy restore --dry-run` - Preview what would be restored
- Confirm before overwriting existing files

### Error Handling Approach
- Check rsync exit codes
- Validate paths before operations
- Provide clear error messages
- Add rollback for failed operations

### Better Defaults
- Auto-detect common cloud storage:
  - iCloud Drive
  - Dropbox
  - Google Drive
  - OneDrive
- Fall back to `~/.juvy-backup` if no cloud storage found

### Configuration Enhancement
- Keep simple text-based config
- Add comments to config files
- Support environment variables for override

## Next Steps
1. Implement restore functionality with proper error handling
2. Add path validation throughout
3. Create comprehensive help/usage system
4. Test with different macOS setups
5. Set up GitHub repository with proper README
6. Create installation script