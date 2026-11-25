#!/usr/bin/env bash
# Creates the Android upload key for EduOS Teacher and writes android/key.properties.
# Run on a trusted computer. keytool asks for the passwords; they are never shown or stored anywhere else.
# Keep the .jks file and its passwords safe (e.g. in the Ministry's password manager) and back them up:
# Google Play needs this key for every future update.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="${KEY_DIR:-$HOME/.eduos-keys}"
mkdir -p "$dir" && chmod 700 "$dir"
jks="$dir/eduos-teacher-upload.jks"
if [ -e "$jks" ]; then echo "$jks already exists. Not overwriting it."; exit 1; fi
keytool -genkeypair -v -keystore "$jks" -alias eduos-upload -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Osun EduOS, O=Osun State Ministry of Education, L=Osogbo, ST=Osun, C=NG"
chmod 600 "$jks"
read -rsp "Type the keystore password again (to save in android/key.properties): " pw; echo
cat > android/key.properties <<PROPS
storeFile=$jks
storePassword=$pw
keyAlias=eduos-upload
keyPassword=$pw
PROPS
chmod 600 android/key.properties
echo "Done. Release builds are now signed with $jks."
echo "android/key.properties is git-ignored. Never commit it or the .jks file."
