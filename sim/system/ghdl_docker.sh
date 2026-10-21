#!/bin/sh
# Run a command in the GHDL container with the repository mounted; cwd = sim/system/work/vhdl.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec docker run --rm --platform linux/amd64 -v "$ROOT":/w -w /w/sim/system/work/vhdl hdlc/ghdl:yosys "$@"
