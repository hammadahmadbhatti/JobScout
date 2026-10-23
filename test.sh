#!/bin/bash
# Runs the JobScoutCore unit tests. With only the Command Line Tools installed
# (no Xcode), Swift Testing lives outside the default search paths, and its
# Foundation cross-import overlay ships without a module, hence the flags.
set -euo pipefail
cd "$(dirname "$0")"
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [ -d "$F/Testing.framework" ]; then
    swift test \
        -Xswiftc -F -Xswiftc "$F" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" "$@"
else
    swift test "$@"
fi
