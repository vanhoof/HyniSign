#!/bin/bash
# check-build.sh — smoke tests for the built HyniSign.dylib.
#
# Verifies architecture, install name, framework dependencies, expected
# wrapper symbols, and the rebound symbol-name strings. Run after `make`
# from the project root:
#
#   bash tests/check-build.sh

set -e

DYLIB="${1:-build/HyniSign.dylib}"

if [ ! -f "$DYLIB" ]; then
    echo "ERROR: $DYLIB not found. Run 'make' from the project root first." >&2
    exit 1
fi

failed=0
check() {
    local name="$1"
    local cond="$2"
    if [ "$cond" = "ok" ]; then
        printf "  ok    %s\n" "$name"
    else
        printf "  FAIL  %s — %s\n" "$name" "$cond"
        failed=$((failed + 1))
    fi
}

echo "Checking $DYLIB..."

# Architecture: arm64 only.
archs=$(lipo -archs "$DYLIB" 2>/dev/null || echo "?")
if [ "$archs" = "arm64" ]; then
    check "arm64-only architecture" ok
else
    check "arm64-only architecture" "got '$archs'"
fi

# Install name.
iname=$(otool -D "$DYLIB" | tail -n +2 | tr -d '[:space:]')
expected_iname="@executable_path/HyniSign.dylib"
if [ "$iname" = "$expected_iname" ]; then
    check "install_name=$expected_iname" ok
else
    check "install_name=$expected_iname" "got '$iname'"
fi

# Required framework dependencies.
linkage=$(otool -L "$DYLIB")
for fw in Foundation CoreFoundation Security; do
    if echo "$linkage" | grep -q "/${fw}.framework/${fw}"; then
        check "links ${fw}.framework" ok
    else
        check "links ${fw}.framework" "missing"
    fi
done

# Must NOT depend on CydiaSubstrate (fishhook is statically linked).
if echo "$linkage" | grep -q "CydiaSubstrate"; then
    check "no CydiaSubstrate dependency" "found CydiaSubstrate in load commands"
else
    check "no CydiaSubstrate dependency" ok
fi

# Wrapper functions are present in the symbol table.
syms=$(nm "$DYLIB" 2>/dev/null || true)
for sym in my_SecItemAdd my_SecItemCopyMatching my_SecItemUpdate my_SecItemDelete my_SecKeyCreateRandomKey my_SecKeyGeneratePair; do
    if echo "$syms" | grep -q " _${sym}\$"; then
        check "defines ${sym}" ok
    else
        check "defines ${sym}" "symbol not found"
    fi
done

# The rebound symbol names appear as constant strings (rebs[] entries).
strings_out=$(strings "$DYLIB")
for name in SecItemAdd SecItemCopyMatching SecItemUpdate SecItemDelete SecKeyCreateRandomKey SecKeyGeneratePair; do
    if echo "$strings_out" | grep -qx "$name"; then
        check "rebinds ${name}" ok
    else
        check "rebinds ${name}" "string not found"
    fi
done

# Helper: HyniSignCopyStripped should be reachable from the dylib (extracted helper).
if echo "$syms" | grep -q "HyniSignCopyStripped"; then
    check "HyniSignCopyStripped present" ok
else
    check "HyniSignCopyStripped present" "symbol not found"
fi

echo
if [ "$failed" -eq 0 ]; then
    echo "All build smoke tests passed."
    exit 0
else
    echo "$failed check(s) failed." >&2
    exit 1
fi
