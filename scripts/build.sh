#!/bin/bash
# Wrapper for the Claude Code agent's bash sessions: sets JAVA_HOME and PATH so the
# gradle invocation works without needing per-call `export ... && export ... && ...`
# chains (which trip the permission allowlist).
#
# Safe to run from any bash; if JAVA_HOME / PATH already point at Java 17 and the
# gradle wrapper, this just exec's gradle straight through.
#
# Usage:  ./scripts/build.sh :fabric:build -p D:/git/github/dovholuknf/ziti-minecraft --no-daemon -q
set -e

if [ -z "$JAVA_HOME" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
    export JAVA_HOME='/c/Program Files/Eclipse Adoptium/jdk-17.0.17.10-hotspot'
fi
export PATH="$JAVA_HOME/bin:$PATH"

GRADLE_BIN='/d/tools/gradle/8.6/bin/gradle'
if [ ! -x "$GRADLE_BIN" ]; then
    echo "gradle not found at $GRADLE_BIN" >&2
    exit 1
fi

exec "$GRADLE_BIN" "$@"
