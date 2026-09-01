#!/bin/bash
# check-link.sh - show the negotiated link state and the target-speed register
# for every endpoint/root-port pair in LINKS. Run on the host at any time.
#
# Healthy after the cap: LnkSta on each root port reports "Speed 16GT/s" and
# every LnkCtl2 target field reads Gen 4 (low nibble = 4).

LINKS="${LINKS:-01:00.0:00:01.0 02:00.0:00:01.1}"   # endpoint:rootport pairs

for pair in $LINKS; do
    for bdf in "${pair%:*:*}" "${pair#*:*:}"; do
        echo "== $bdf  $(lspci -s "$bdf" | cut -d' ' -f2-)"
        lspci -vvs "$bdf" 2>/dev/null | grep -E "LnkCap:|LnkSta:|LnkCtl2:" | sed 's/^/   /'
        printf '   LnkCtl2 raw = 0x%s (target gen = low nibble)\n' "$(setpci -s "$bdf" CAP_EXP+30.w)"
    done
done
