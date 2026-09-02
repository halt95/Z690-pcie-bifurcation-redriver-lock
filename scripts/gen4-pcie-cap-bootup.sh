#!/bin/bash
# gen4-pcie-cap-bootup.sh
#
# Force a PCIe Gen 4 link cap on a redriver-fed slot that the board insists on
# training at Gen 5. Writes the Link Control 2 "Target Link Speed" field on
# BOTH the endpoint and its root port, then retrains the root port.
#
# Unraid User Scripts schedule:  "At First Array Start Only"
#
# Notes
#   - Only binds on a cold boot (full power off). On a warm reboot the
#     firmware rewrites the register within ~2 s and the cap is lost.
#   - Does NOT start any VM. The companion gen4-pcie-cap-array-startup.sh
#     re-applies the cap and starts the VM that owns the card.
#   - Writing the root port alone does not stick; both writes are required.
#
# ---- EDIT THESE FOR YOUR HOST -------------------------------------------
# Find them with:  lspci -nn | grep -i nvidia     (endpoint BDFs)
#                  lspci -t                       (root port each endpoint hangs off)
# One "endpoint=rootport" pair per GPU behind the redriver. Space separated.
LINKS="${LINKS:-01:00.0=00:01.0 02:00.0=00:01.1}"
TARGET_GEN="${TARGET_GEN:-4}"       # 1..5; LnkCtl2 target link speed
# -------------------------------------------------------------------------

set -u
LOG_TAG="[gen4-cap-bootup]"

echo "$LOG_TAG $(date) Starting"
echo "$LOG_TAG Uptime: $(uptime -p)"

for pair in $LINKS; do
    for bdf in "${pair%=*}" "${pair#*=}"; do
        if ! lspci -s "$bdf" >/dev/null 2>&1; then
            echo "$LOG_TAG ERROR: PCIe device $bdf not found - aborting"
            exit 1
        fi
    done
done

printf -v TARGET_WORD '%04x' "$TARGET_GEN"

# CAP_EXP+30 = Link Control 2; low nibble = target link speed (1=2.5GT/s .. 5=32GT/s).
# Written with mask 000f so the other LnkCtl2 bits are left untouched.
# CAP_EXP+10 = Link Control;  bit 5 = Retrain Link
for pair in $LINKS; do
    ep="${pair%=*}"; rp="${pair#*=}"
    echo "$LOG_TAG Pre-cap link $ep <- $rp:"
    lspci -vvs "$rp" 2>/dev/null | grep -E "LnkCap:|LnkSta:" | sed "s/^/$LOG_TAG   /" || true
    echo "$LOG_TAG Capping endpoint $ep LnkCtl2 -> Gen $TARGET_GEN..."
    setpci -s "$ep" CAP_EXP+30.w="$TARGET_WORD:000f"
    echo "$LOG_TAG Capping root port $rp LnkCtl2 -> Gen $TARGET_GEN..."
    setpci -s "$rp" CAP_EXP+30.w="$TARGET_WORD:000f"
    echo "$LOG_TAG Retraining root port $rp..."
    setpci -s "$rp" CAP_EXP+10.w=20:20
done

sleep 1

for pair in $LINKS; do
    rp="${pair#*=}"
    echo "$LOG_TAG Post-cap link $rp:"
    lspci -vvs "$rp" 2>/dev/null | grep -E "LnkCap:|LnkSta:" | sed "s/^/$LOG_TAG   /" || true
done

echo "$LOG_TAG $(date) Done - VM start is handled by the array-startup script"
exit 0
