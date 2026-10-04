#ifdef CID(Native.nanoseconds)
static Term cooking_entities_nanoseconds_run(Env e, Term* f, IoWork* w) {
  u64 ns = io_tick();
  return io_tup(e, (u32)(ns >> 32), (u32)ns);
}
static void __attribute__((constructor)) cooking_entities_nanoseconds_use(void) {
  io_eff(CID(Native.nanoseconds), cooking_entities_nanoseconds_run, 0);
}
#endif
