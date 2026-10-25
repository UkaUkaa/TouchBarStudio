#!/bin/zsh
# Runs the unit tests. With only the Command Line Tools installed, SwiftBuild can lose
# the Swift Testing macro plugin on incremental builds ("plugin for module
# 'TestingMacros' not found"); passing its path explicitly avoids that.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  swift test "$@"
fi
