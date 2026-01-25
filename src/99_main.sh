## MAIN ENTRY POINT ############################################################

# When executed directly (not sourced), run the juvy command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  juvy "$@"
fi
