#!/bin/bash
# gen4-pcie-cap-array-startup.sh
#
# Re-apply the Gen 4 link cap (idempotent), then start the VM that owns the
# card. Companion to gen4-pcie-cap-bootup.sh, which does the first cap of the
# boot; this one runs on every array start and races the firmware rewrite by
# starting the VM straight after the cap.
#
# Unraid User Scripts schedule:  "At Startup of Array"
#
# CRITICAL: disable Autostart for VM_NAME in the Unraid UI (VMs -> <vm> ->
# Autostart OFF). Otherwise autostart fires before this script, the VM issues
# a Function Level Reset on the uncapped link and it retrains at Gen 5.
#
# ---- EDIT THESE FOR YOUR HOST -------------------------------------------
# One "endpoint=rootport" pair per GPU behind the redriver. Space separated.
LINKS="${LINKS:-01:00.0=00:01.0 02:00.0=00:01.1}"
TARGET_GEN="${TARGET_GEN:-4}"       # 1..5; LnkCtl2 target link speed
VM_NAME="${VM_NAME:-myvm}"          # libvirt name of the VM that owns the GPUs
# -------------------------------------------------------------------------

set -u
LOG_TAG="[gen4-cap-array]"

echo "$LOG_TAG $(date) Starting"

for pair in $LINKS; do
    for bdf in "${pair%=*}" "${pair#*=}"; do
        if ! lspci -s "$bdf" >/dev/null 2>&1; then
            echo "$LOG_TAG ERROR: PCIe device $bdf not found - aborting"
            exit 1
        fi
    done
done

printf -v TARGET_WORD '%04x' "$TARGET_GEN"

# Defensive re-cap (no-op if the bootup script already applied it)
for pair in $LINKS; do
    ep="${pair%=*}"; rp="${pair#*=}"
    echo "$LOG_TAG Re-applying cap on $ep <- $rp (Gen $TARGET_GEN)..."
    setpci -s "$ep" CAP_EXP+30.w="$TARGET_WORD:000f"
    setpci -s "$rp" CAP_EXP+30.w="$TARGET_WORD:000f"
    setpci -s "$rp" CAP_EXP+10.w=20:20
done

sleep 1

for pair in $LINKS; do
    rp="${pair#*=}"
    echo "$LOG_TAG Link $rp before VM start:"
    lspci -vvs "$rp" 2>/dev/null | grep -E "LnkSta:" | sed "s/^/$LOG_TAG   /" || true
done

# Start the VM immediately - do not add a sleep here
if ! virsh list --all 2>/dev/null | awk 'NR>2 {print $2}' | grep -qx "$VM_NAME"; then
    echo "$LOG_TAG WARN: VM '$VM_NAME' not defined; cap applied but VM not started"
elif virsh list --state-running 2>/dev/null | awk 'NR>2 {print $2}' | grep -qx "$VM_NAME"; then
    echo "$LOG_TAG VM '$VM_NAME' already running - no VM action needed"
else
    echo "$LOG_TAG Starting VM '$VM_NAME'..."
    if virsh start "$VM_NAME"; then
        echo "$LOG_TAG VM '$VM_NAME' start issued OK"
    else
        echo "$LOG_TAG ERROR: virsh start failed - check the Unraid VM log"
        exit 2
    fi
fi

echo "$LOG_TAG $(date) Done"
exit 0
