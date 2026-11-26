#!/bin/bash
# Passes the test macro plugin path explicitly. With Command Line Tools and no Xcode, the first
# build after a clean leaves it out and fails with "plugin for module 'TestingMacros' not found".
set -euo pipefail
cd "$(dirname "$0")/.."

plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
# Xcode keeps the plugin elsewhere and finds it without help, so the flag is only for Command Line Tools.
if [ -d "$plugins" ]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
else
  swift test "$@"
fi
