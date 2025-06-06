emulate -L zsh

JUVY_CONFIG_DIR=$HOME/.config/juvy
JUVY_CONFIG=$JUVY_CONFIG_DIR/config
JUVY_BACKUP=$JUVY_CONFIG_DIR/backup

if [[ -f $JUVY_CONFIG ]]; then
  source "$JUVY_CONFIG"
fi

: ${JUVY_BACKUP_DIR:="$HOME/Library/Mobile\ Documents/com~apple~CloudDocs/juvy"}

juvy() {
  case $1 in
    "install")
      _juvy_install $@
      ;;
    "init")
      _juvy_init $@
      ;;
    "rm")
      print "juvy: Are you sure you want to remove the configuration and backup directories? [y/N]"
      read -r "confirm?"
      if [[ $confirm == "y" ]]; then
        _juvy_rm $@
      fi
      ;;
    "backup")
      _juvy_backup $@
      ;;
    *)
      print "juvy: Unknown command '$1'" >&2
      ;;
  esac
}

_juvy_init() {
  if ! [[ -d $JUVY_CONFIG_DIR ]]; then
    mkdir -p $JUVY_CONFIG_DIR > /dev/null 2>&1
  fi

  if ! [[ -f $JUVY_BACKUP ]]; then
    print "/.zshrc\n/.gitconfig" >> $JUVY_BACKUP
  fi

  if ! [[ -f $JUVY_CONFIG ]]; then
    touch $JUVY_CONFIG
  fi

  _juvy_init_backups
}

_juvy_init_backups() { 
  if  [[ -z $(grep "JUVY_BACKUP_DIR=" $JUVY_CONFIG) ]]; then
    printf "juvy: Where do you want backups to be stored? (enter for default: %s)" $JUVY_BACKUP_DIR
    read -r "dir?"

    if [[ -n $dir ]]; then
      if mkdir -p $dir > /dev/null 2>&1; then
        JUVY_BACKUP_DIR=$dir
      else
        printf "juvy: Unable to create backup directory (%s). Falling back to default (%)" $dir $JUVY_BACKUP_DIR
      fi
    fi

    print -r "JUVY_BACKUP_DIR=$JUVY_BACKUP_DIR" > $JUVY_CONFIG
  fi 

  if ! [[ -d "$JUVY_BACKUP_DIR/.git" ]]; then
    git init -b main $JUVY_BACKUP_DIR
  fi
}

_juvy_rm() {
  rm -rf $JUVY_CONFIG_DIR
  rm -rf $JUVY_BACKUP_DIR
  print "juvy: Removed configuration and backup directories"
}

_juvy_backup() {
  if [[ -d $JUVY_BACKUP_DIR ]]; then
    rsync -a --files-from="$JUVY_BACKUP" "$HOME" "$JUVY_BACKUP_DIR"
    if [[ -n $(_juvy_git status --porcelain) ]]; then
      _juvy_git add .
      _juvy_git commit -m "Backup: $(_juvy_timestamp)"
    fi
  else
    printf "juvy: Set JUVY_BACKUP_DIR value in %s" $JUVY_CONFIG >&2
  fi
}

_juvy_timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

_juvy_git() {
  if [[ -d $JUVY_BACKUP_DIR ]]; then
    git -C $JUVY_BACKUP_DIR $@
  fi
}

_juvy_install() {
  local install_path="$HOME/.juvy.zsh"
  local script_path="${(%):-%x}"
  
  # Check if being piped from curl (no script path or stdin)
  if [[ -z "$script_path" ]] || [[ "$script_path" == "zsh" ]] || [[ ! -f "$script_path" ]]; then
    # We're being piped - need to download the script
    print "juvy: Downloading latest version..."
    curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/juvy.zsh -o "$install_path" || {
      print "juvy: Failed to download juvy" >&2
      return 1
    }
    print "juvy: Downloaded to $install_path"
  else
    # Check if already installed
    if [[ -f $install_path ]] && [[ $script_path != $install_path ]]; then
      print "juvy: Already installed at $install_path"
      print "juvy: Do you want to update the installation? [y/N]"
      read -r "update?"
      if [[ $update != "y" ]]; then
        return 0
      fi
    fi
    
    # Copy script to home directory
    if [[ $script_path != $install_path ]]; then
      cp "$script_path" "$install_path" || {
        print "juvy: Failed to copy script to $install_path" >&2
        return 1
      }
      print "juvy: Installed to $install_path"
    fi
  fi
  
  # Check if already in .zshrc
  if ! grep -q "source.*\.juvy\.zsh" "$HOME/.zshrc" 2>/dev/null; then
    print "\n# juvy dotfile backup tool" >> "$HOME/.zshrc"
    print "source $install_path" >> "$HOME/.zshrc"
    print "juvy: Added to .zshrc"
  else
    print "juvy: Already in .zshrc"
  fi
  
  # Check for existing configuration
  if [[ -f $JUVY_CONFIG ]] && [[ -f $JUVY_BACKUP ]]; then
    print "juvy: Existing configuration found"
    print "juvy: Run 'juvy backup' to backup your files"
  else
    print "\njuvy: No configuration found. Would you like to set it up now? [Y/n]"
    read -r "setup?"
    if [[ $setup != "n" ]]; then
      print "juvy: Starting setup..."
      _juvy_init
    else
      print "juvy: Run 'juvy init' to set up later"
    fi
  fi
  
  print "\njuvy: Installation complete!"
  print "juvy: Restart your shell or run 'source ~/.zshrc' to use juvy"
}

# Auto-run install if script is being piped (curl install)
if [[ -z "${(%):-%x}" ]] || [[ "${(%):-%x}" == "zsh" ]]; then
  juvy install
fi
