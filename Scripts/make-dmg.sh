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

# Set NOTARY_PROFILE (a `notarytool store-credentials` keychain profile) to
# notarize and staple the dmg. Requires CODESIGN_IDENTITY in make-app.sh too.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit dist/SkillManager.dmg \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple dist/SkillManager.dmg
fi

echo "Built dist/SkillManager.dmg"
