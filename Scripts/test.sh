#!/bin/zsh
# Runs unit tests. The extra flags point swift test at the Swift Testing
# framework bundled with Command Line Tools (no full Xcode installed).
set -euo pipefail
cd "$(dirname "$0")/.."

FWK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

if [[ -d "$FWK" ]]; then
    exec swift test \
        -Xswiftc -F"$FWK" \
        -Xlinker -F"$FWK" \
        -Xlinker -rpath -Xlinker "$FWK" \
        -Xlinker -rpath -Xlinker "$LIB" \
        "$@"
else
    # Full Xcode installed: plain swift test works.
    exec swift test "$@"
fi
