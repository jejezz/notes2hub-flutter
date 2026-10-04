#!/usr/bin/env bash
#
# `flutter`를 그대로 부르되, 저장소 루트에 dart_defines.local.json이 있으면
# --dart-define-from-file로 넘겨서 로컬 개발용 값(GitHub Client ID 등)을 채운다.
# 이 파일은 git에 올라가지 않는다 (.gitignore). 견본: dart_defines.local.example.json
#
#   tool/flutter_local.sh run -d macos
#   tool/flutter_local.sh build macos --debug
#   tool/flutter_local.sh test
#
# run / build / test / drive 에만 값을 붙이고, 나머지 하위 명령은 그대로 넘긴다.
# FLUTTER_LOCAL_DRY_RUN=1 이면 실행하지 않고 명령만 출력한다.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES="$ROOT/dart_defines.local.json"
cd "$ROOT"

args=("$@")
case "${1:-}" in
  run | build | test | drive)
    if [ -f "$DEFINES" ]; then
      python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d,dict)' "$DEFINES" 2>/dev/null \
        || { echo "dart_defines.local.json is not a valid JSON object — fix it or delete it." >&2; exit 1; }
      echo "[flutter_local] using dart_defines.local.json ($(python3 -c 'import json,sys; print(", ".join(json.load(open(sys.argv[1]))))' "$DEFINES"))" >&2
      args+=("--dart-define-from-file=$DEFINES")
    else
      echo "[flutter_local] no dart_defines.local.json — building without local defines (copy dart_defines.local.example.json to create it)." >&2
    fi
    ;;
esac

if [ "${FLUTTER_LOCAL_DRY_RUN:-}" = "1" ]; then
  echo flutter "${args[@]}"
else
  exec flutter "${args[@]}"
fi
