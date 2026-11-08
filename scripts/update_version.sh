#!/usr/bin/env bash
# Usage: scripts/update_version.sh <version> <build-number>   e.g. 1.2.3 14
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <version> <build-number>" >&2
  exit 1
fi

VERSION="$1"
BUILD="$2"
cd "$(dirname "$0")/.."

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Invalid version '$VERSION' or build '$BUILD'" >&2
  exit 1
fi

sed -i -E "s/^version:.*/version: ${VERSION}+${BUILD}/" pubspec.yaml
grep '^version:' pubspec.yaml
