#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$TASK_ROOT"
mkdir -p .test-bin
"${CXX:-c++}" -std=c++20 -O2 -Wall -Wextra -Werror \
  mod-multibot-bridge/tests/random_bot_directory_test.cpp -o .test-bin/directory-test
.test-bin/directory-test
cd MultiBot
"${LUAC:-luac5.1}" -p Core/MultiBotComm.lua Features/MultiBotRandomBotDirectory.lua \
  UI/MultiBotRandomBotDirectoryUI.lua UI/MultiBotUnitsRootUI.lua tests/random_bot_directory_test.lua
"${LUA:-lua5.1}" tests/random_bot_directory_test.lua
