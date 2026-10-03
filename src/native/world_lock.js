// No silent fallback to an unlocked world in the JS backend.
function mc_world_lease_unavailable() { return io_fail(95); }
io_eff(CID(Native.acquire), mc_world_lease_unavailable);
io_eff(CID(Native.release), mc_world_lease_unavailable);
