#!/bin/zsh
# Just Type It – uninstaller · Created by Stefano Roman Gunness · MIT License
pkill -x JustTypeIt 2>/dev/null || true
rm -rf ~/Applications/"Just Type It.app"
read "?Also delete your documents and settings? [y/N] " a
[[ "$a" == [yY]* ]] && rm -rf ~/Library/Application\ Support/JustTypeIt
security delete-keychain ~/Library/Keychains/justtypeit-signing.keychain-db 2>/dev/null || true
echo "Just Type It was removed."
