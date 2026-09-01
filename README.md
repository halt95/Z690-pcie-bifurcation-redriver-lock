# Z690 PCIe bifurcation redriver lock

Pinning a PCIe link to Gen 4 on an ASUS Z690 board whose bifurcated x8/x8 slot
feeds a Gen 4 redriver. The board trains the link at Gen 5 no matter what the
BIOS says, the redriver cannot carry Gen 5, and the result is either a link
full of silent CRC replays or a card that drops off the bus under load.

Two small Unraid User Scripts fix it. The method (dual Link Control 2 write plus
retrain, applied between array start and VM start, after a hard power cycle)
should carry over to any Linux host with `setpci`, not just Unraid.

## Hardware

| Part | Detail |
|---|---|
| Motherboard | ASUS Prime Z690-P D4 |
| CPU | Intel Core i9-14900K |
| RAM | 128 GB DDR4-3200 |
| Slot | CPU primary x16, bifurcated x8/x8 in BIOS; both legs go through the redriver |
| Redriver | C-Payne SlimSAS PCIe Gen 4 x8x8 host adapter (TI DS160PR810 redriver chips, rated to 16 GT/s) |
| GPUs | 2x NVIDIA RTX 5060 Ti 16 GB (PCIe Gen 5 devices), one on each x8 leg of the redriver |
| Hypervisor | Unraid, GPU passed through with VFIO to a Linux VM |
| BIOS / Unraid version | v3811 / 7.2.4 |

The same slot has since carried other cards behind the same redriver; the
behaviour is a property of the board plus redriver, not of the card.

## Symptoms

- The link trains at **Gen 5 x8** even though the redriver is Gen 4 only.
- PCIe retries CRC errors silently at roughly 5K-19K replays per second under
  load. `nvidia-smi -q` showed `Replays Since Reset` at 13 million after eight
  hours of inference. Visible cost is about 1-2% bandwidth and jittery latency.
- Worst case, under the first sustained DMA burst (a large model load), the
  link dies, the card disappears from the bus (Xid 79 class) and the VFIO
  guest hangs.

## What does not work

- **BIOS `Max Link Speed = Gen 4`** under System Agent Configuration. The
  setting is accepted but the endpoint still negotiates Gen 5. (A later
  incident on the same slot was resolved by a per-slot Gen 4 setting in BIOS;
  see History. If your board exposes a per-slot option, try it first.)
- **Warm reboot** of any kind. Two problems: firmware rewrites Link Control 2
  back to Gen 5 within about two seconds of a write, and the board sometimes
  fails to bring the bifurcated links up at all after a warm restart. The only
  recovery seen was a full power off.
- **Writing the root port only.** The cap does not stick; the next Function
  Level Reset (any VM start) retrains at Gen 5.

## What works

1. **Hard shutdown** the host (full power off), then power on.
2. After the array is up and **before the VM starts**, write the target link
   speed on **both** the endpoint and its root port, then retrain:

   ```
   # repeat for every GPU behind the redriver (endpoint, then its root port)
   setpci -s 01:00.0 CAP_EXP+30.w=0004   # GPU 1 endpoint  LnkCtl2 target = Gen 4
   setpci -s 00:01.0 CAP_EXP+30.w=0004   # GPU 1 root port LnkCtl2 target = Gen 4
   setpci -s 00:01.0 CAP_EXP+10.w=20:20  # retrain
   setpci -s 02:00.0 CAP_EXP+30.w=0004   # GPU 2 endpoint
   setpci -s 00:01.1 CAP_EXP+30.w=0004   # GPU 2 root port
   setpci -s 00:01.1 CAP_EXP+10.w=20:20  # retrain
   ```

3. Start the VM **immediately**. No sleep in between; the VM start has to land
   inside the window before firmware rewrites the register.

Verified result: every card shows `pcie.link.gen.max = 4` in the guest, `Replays Since Reset = 0`
after sustained inference load, decode throughput unchanged from the uncapped
baseline.

## Install (Unraid)

Both scripts go into the **User Scripts** plugin (Settings -> User Scripts ->
Add New Script, paste the file, set the schedule). On disk they live at
`/boot/config/plugins/user.scripts/scripts/<name>/script`.

| Script | Schedule | Does |
|---|---|---|
| `scripts/gen4-pcie-cap-bootup.sh` | At First Array Start Only | dual cap + retrain, no VM action |
| `scripts/gen4-pcie-cap-array-startup.sh` | At Startup of Array | re-apply cap, then `virsh start` the VM |

Edit the block at the top of each script:

| Variable | Meaning | How to find it |
|---|---|---|
| `LINKS` | space-separated `endpoint:rootport` pairs, one per GPU behind the redriver | endpoints: `lspci -nn \| grep -i nvidia`; root ports: `lspci -t` |
| `TARGET_GEN` | target link speed, 4 for a Gen 4 redriver | redriver datasheet |
| `VM_NAME` | libvirt name of the VM that owns the GPUs | `virsh list --all` |

**Prerequisite:** the VM that owns the card must have **Autostart OFF** in the
Unraid UI. Otherwise autostart fires before the script, the VM issues an FLR on
the uncapped link and it retrains at Gen 5. VMs whose GPUs are on direct slots
can keep autostart on.

`scripts/check-link.sh` prints the negotiated link state and the raw Link
Control 2 register for every pair in `LINKS`.

**Revert:** delete both User Scripts and re-enable VM autostart.

## Verify

A real cold-boot run with both scripts' output is in
`docs/sample-run-2026-08-25.md`.

```
# in the guest (or on a bare host)
nvidia-smi --query-gpu=pcie.link.gen.max,pcie.link.gen.current,pcie.link.width.current --format=csv
nvidia-smi -q | grep -A3 Replay          # must stay 0 under load

# on the host
scripts/check-link.sh
```

An idle Ampere or Blackwell card reporting `gen.current = 1` is normal link
power management, not a fault. Judge by `gen.max` and by the replay counter
under load.

## History

- **2026-05-20** — Problem characterised on the Unraid host (replay storm at
  Gen 5 x8, 13M replays in 8 h). Manual recipe found and verified: hard power
  cycle, dual LnkCtl2 write on endpoint and root port from the Unraid shell,
  retrain, immediate `virsh start`. Root-port-only writes and the BIOS
  System Agent `Max Link Speed` setting ruled out. Inference benchmarks re-run
  the same afternoon with the cap in place: zero replays, no throughput loss.
- **2026-05-21** — Recipe automated as two scripts in the Unraid **User
  Scripts** plugin: `gen 4 pcie cap - bootup` (At First Array Start Only) and
  `gen 4 pcie cap - array startup` (At Startup of Array). VM autostart disabled
  in the Unraid UI as the prerequisite. A combined single-script version was
  kept alongside as a runbook.
- **2026-05-27** — Script update: the card was reassigned to a different VM, so
  `VM_NAME` in the array-startup script was changed and the autostart rule
  re-applied to the new owner. Cap re-verified in the new guest: Gen 4 x8,
  zero replays.
- **2026-08-09** — A card behind the same redriver dropped off the bus during
  a model load and hung the guest. Recovered by forcing the slot to Gen 4 in
  BIOS, which held across reboots. Recorded here as an alternative to the
  scripts on boards that expose a per-slot speed setting.
- **2026-09-01** — Repo created. Both User Scripts normalised (edit-me block at
  the top, a `LINKS` list of endpoint/root-port pairs so every GPU behind the
  redriver is capped, target speed and VM name as variables),
  `check-link.sh` added, and the hard-shutdown requirement written down.

## Why it happens (best current understanding)

The DS160PR810 is an analog redriver, transparent to link training. The board
advertises Gen 5 on the root port, the Gen 5 endpoint accepts, and neither side
knows there is a Gen 4 part in between. Equalisation "succeeds" at 32 GT/s with
a marginal eye, so the link stays up but every heavy transfer sheds CRC errors.
Link Control 2 on both ends is the only lever that survives the retrain, and
this board's firmware polices that register on warm boots.

## Licence

MIT. See `LICENSE`.
