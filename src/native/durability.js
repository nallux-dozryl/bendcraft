// This boundary is verified on native POSIX. JS has no macOS full-sync path.
function mc_durability_unavailable() { return io_fail(95); }
io_eff(CID(Durability.create), mc_durability_unavailable);
io_eff(CID(Durability.replace), mc_durability_unavailable);
io_eff(CID(Durability.sync_directory), mc_durability_unavailable);
io_eff(CID(Durability.remove), mc_durability_unavailable);
function mc_durability_sync_unavailable(file) { return io_tup(file, io_fail(95)); }
io_eff(CID(Durability.sync), mc_durability_sync_unavailable);
