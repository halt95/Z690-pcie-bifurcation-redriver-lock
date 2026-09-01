# Z690-pcie-bifurcation-redriver-lock
Pin bifurcated x8/x8 PCIe links to Gen 4 on an ASUS Z690 that ignores its BIOS speed setting. Unraid User Scripts write LnkCtl2 on endpoint and root port, retrain, then start the VM before firmware reverts. Fixes CRC replay storms and bus drops with C-Payne Gen 4 redrivers and Gen 5 GPUs.
