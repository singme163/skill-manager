#!/bin/zsh
# Builds SkillManager.app (via make-app.sh) and wraps it into a distributable
# dmg with an /Applications shortcut. Output: dist/SkillManager.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/make-app.sh

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R dist/SkillManager.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f dist/SkillManager.dmg
hdiutil create \
    -volname "Skill Manager" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    dist/SkillManager.dmg

echo "Built dist/SkillManager.dmg"
