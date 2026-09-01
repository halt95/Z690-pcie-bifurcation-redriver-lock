# Sample run — 2026-08-25, cold boot of the Unraid host

Both User Scripts fired at array start, four minutes after power-on. Output is
copied from the User Scripts plugin log viewer
(`/tmp/user.scripts/tmpScripts/<script name>/log.txt`). This was the
single-endpoint version of the scripts, before the `LINKS` list was added.

## gen 4 pcie cap - bootup  (At First Array Start Only)

```
[gen4-cap-bootup] Tue Aug 25 20:51:50 BST 2026 Starting
[gen4-cap-bootup] Uptime: up 4 minutes
[gen4-cap-bootup] Pre-cap root-port link:
[gen4-cap-bootup]   LnkCap: Port #4, Speed 32GT/s, Width x8, ASPM not supported
[gen4-cap-bootup]   LnkSta: Speed 16GT/s, Width x8
[gen4-cap-bootup] Capping GPU endpoint 02:00.0 LnkCtl2 → Gen 4...
[gen4-cap-bootup] Capping root port 00:01.1 LnkCtl2 → Gen 4...
[gen4-cap-bootup] Triggering retrain on root port...
[gen4-cap-bootup] Post-cap root-port link:
[gen4-cap-bootup]   LnkCap: Port #4, Speed 32GT/s, Width x8, ASPM not supported
[gen4-cap-bootup]   LnkSta: Speed 16GT/s, Width x8
[gen4-cap-bootup] Tue Aug 25 20:51:51 BST 2026 Done — VM start handled by array-startup script
```

## gen 4 pcie cap - array startup  (At Startup of Array)

```
[gen4-cap-array] Tue Aug 25 20:51:50 BST 2026 Starting
[gen4-cap-array] Re-applying dual cap...
[gen4-cap-array] Root-port link state before VM start:
[gen4-cap-array]   LnkSta: Speed 16GT/s, Width x8
[gen4-cap-array] WARN: VM 'debby' not defined; cap applied but VM not started
[gen4-cap-array] Tue Aug 25 20:51:51 BST 2026 Done
```

## Reading it

- `LnkCap` still advertises 32 GT/s (Gen 5): the root port's capability is
  untouched, only the target speed is pinned. `LnkSta` at 16 GT/s x8 is the
  goal state.
- The link was already at 16 GT/s *before* the cap on this boot. By this date
  the slot had also been forced to Gen 4 in BIOS (see History, 2026-08-09), so
  the scripts were acting as a second guard. The retrain still completed and
  the link stayed at Gen 4 x8.
- Both schedules fire on a cold boot, in the same second. That is expected:
  "At First Array Start Only" and "At Startup of Array" both trigger on the
  first array start after power-on; only the second one fires again on later
  array restarts.
- The `WARN` is the script doing its job: the VM named in `VM_NAME` no longer
  existed on the host, so it capped and stopped rather than failing. Update
  `VM_NAME` when a VM is renamed or moved.
