#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

command -v erlc >/dev/null 2>&1 || {
    printf '%s\n' "Erlang/OTP compiler (erlc) is required. Install Erlang/OTP or use Docker Compose." >&2
    exit 1
}
command -v erl >/dev/null 2>&1 || {
    printf '%s\n' "Erlang runtime (erl) is required. Install Erlang/OTP or use Docker Compose." >&2
    exit 1
}

mkdir -p _build/ebin
for source in src/*.erl; do
    erlc -Werror -o _build/ebin "$source"
done
cp src/telecomerl.app.src _build/ebin/telecomerl.app
export TELECOM_STATIC_DIR="$ROOT/static"
exec erl -pa _build/ebin -noshell -eval 'telecomerl:start(), receive stop -> ok end.'