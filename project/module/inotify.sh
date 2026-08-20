#!/bin/bash
# inotify handler - delete ..5.u.S leftover on creation
EVENT="$1"
FILE="$2"
[ -e "$FILE" ] || exit 0
case "$FILE" in
    */..5.u.S) rm -rf "$FILE" 2>/dev/null ;;
esac
