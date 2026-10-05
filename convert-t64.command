#!/usr/bin/env bash
# Double-click (macOS) to turn every .t64 on the Pocket card's Assets/c64/common into a .prg.
# Runs tools/t64_to_prg.py, which finds the card by itself.
cd "$(dirname "$0")"
script=tools/t64_to_prg.py
[ -f "$script" ] || script=t64_to_prg.py
if command -v python3 >/dev/null 2>&1; then
	python3 "$script" "$@"
else
	echo "error: python3 is needed (macOS: run  xcode-select --install  once)"
fi
echo
read -r -p "Press Enter to close." _
