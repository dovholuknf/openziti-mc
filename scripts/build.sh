#!/bin/bash
# Wrapper for gradle invocations -- sets JAVA_HOME and PATH so the build works
# without needing per-call `export ... && export ... && ...` chains in callers.
#
# MC 1.21.4 needs Java 21. We try, in order:
#   1. Existing $JAVA_HOME if it points at a Java 21+ JDK.
#   2. `java` on PATH if it reports version >= 21.
#   3. Common Windows Temurin install paths under /c/Program Files/Eclipse Adoptium/.
#
# Usage:  ./scripts/build.sh :fabric:build -p D:/git/github/dovholuknf/ziti-minecraft --no-daemon -q
set -e

want_major=21

java_major() {
    # Print the major version of the java at $1, or empty on failure.
    "$1" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/'
}

# 1. Honour existing JAVA_HOME if it's the right major version.
if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    if [ "$(java_major "$JAVA_HOME/bin/java")" -ge "$want_major" ] 2>/dev/null; then
        :  # JAVA_HOME is fine
    else
        unset JAVA_HOME
    fi
fi

# 2. Try `java` on PATH.
if [ -z "$JAVA_HOME" ]; then
    if command -v java >/dev/null 2>&1; then
        if [ "$(java_major java)" -ge "$want_major" ] 2>/dev/null; then
            JAVA_PATH="$(command -v java)"
            export JAVA_HOME="$(dirname "$(dirname "$JAVA_PATH")")"
        fi
    fi
fi

# 3. Probe common Temurin install paths on Windows.
if [ -z "$JAVA_HOME" ]; then
    for candidate in /c/Program\ Files/Eclipse\ Adoptium/jdk-21*; do
        if [ -x "$candidate/bin/java" ]; then
            export JAVA_HOME="$candidate"
            break
        fi
    done
fi

if [ -z "$JAVA_HOME" ]; then
    echo "Could not find a Java $want_major+ JDK. Install Temurin 21: 'choco install temurin21 -y'" >&2
    exit 1
fi

export PATH="$JAVA_HOME/bin:$PATH"

# Prefer the project's gradle wrapper so the Gradle version auto-syncs with
# gradle/wrapper/gradle-wrapper.properties (currently 8.10.2 for Loom 1.7+).
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -x "$REPO_ROOT/gradlew" ]; then
    exec "$REPO_ROOT/gradlew" "$@"
fi

# Fallback to system gradle if the wrapper is missing.
GRADLE_BIN='/d/tools/gradle/8.6/bin/gradle'
if [ ! -x "$GRADLE_BIN" ]; then
    echo "gradle not found at $GRADLE_BIN" >&2
    exit 1
fi
exec "$GRADLE_BIN" "$@"
