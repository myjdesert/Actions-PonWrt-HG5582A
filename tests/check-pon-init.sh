#!/bin/sh
# Unit test for the re-activation decision in fix/pon.init.
#
# pon.init is an /etc/rc.common script, so it cannot be sourced directly.
# The two functions under test are extracted verbatim from the shipped file and
# the sysfs lookups are redirected to a mock directory.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INIT="$HERE/../fix/pon.init"
[ -f "$INIT" ] || { echo "cannot find $INIT" >&2; exit 1; }

MOCK_SYS=$(mktemp -d)
trap 'rm -rf "$MOCK_SYS"' EXIT

# Extract running_mode() and needs_reactivation() as-is, only rewriting the
# hard-coded sysfs prefix.
eval "$(sed -n '/^running_mode()/,/^}/p' "$INIT")"
eval "$(sed -n '/^needs_reactivation()/,/^}/p' "$INIT" |
	sed 's|/sys/class/net/\$device/xpon|$MOCK_SYS|g')"

# Drive the driver-reported mode from the test instead of a real ponctl.
running_mode() { printf '%s' "$MOCK_ACTIVE"; }

fail=0
case_no=0

# name expected active mode pending_serial latched_serial
run_case() {
	name="$1"; expect="$2"; active="$3"; mode="$4"
	pending="$5"; latched="$6"

	case_no=$((case_no + 1))
	MOCK_ACTIVE="$active"
	printf '%s\n' "$pending" >"$MOCK_SYS/serial_number"
	printf '%s\n' "$latched" >"$MOCK_SYS/active_serial_number"

	if needs_reactivation pon0 "$mode"; then
		got=0
	else
		got=1
	fi

	if [ "$got" = "$expect" ]; then
		printf 'PASS  %-46s r=%s\n' "$name" "$got"
	else
		printf 'FAIL  %-46s expect=%s got=%s\n' "$name" "$expect" "$got"
		fail=1
	fi
}

# 0 = must bounce the netdev, 1 = leave it alone
run_case "line up on xgpon, config asks epon"     0 xgpon       epon-10g-1g aa aa
run_case "steady state, mode matches"             1 epon-10g-1g epon-10g-1g aa aa
run_case "line already correct, identity matches" 1 gpon        gpon        aa aa
run_case "line not started (none)"                1 none        epon-10g-1g aa aa
run_case "line not started (empty)"               1 ""          epon-10g-1g aa aa
run_case "identity changed, mode matches"         0 epon-10g-1g epon-10g-1g bb aa
run_case "no mode configured, identity ok"        1 epon-10g-1g ""          aa aa
run_case "serial parked as none"                  1 epon-10g-1g epon-10g-1g none none
run_case "mode changed to gpon"                   0 epon-10g-1g gpon        aa aa
run_case "modeless line, identity changed"        0 xgpon       ""          bb aa

echo
if [ "$fail" -eq 0 ]; then
	echo "all $case_no cases passed"
else
	echo "some cases FAILED"
fi
exit "$fail"
