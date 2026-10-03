// Narrow POSIX durability effects. No save format or gameplay interpretation.
#include <fcntl.h>
#include <unistd.h>

static void mc_create_call(IoWork* w) {
  w->made = (intptr_t)io_sys_end(w, open(w->data, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600));
}

static Term mc_create_pack(Env e, IoWork* w) {
  free(w->data);
  return io_res(e, w, io_hand(w->made));
}

#ifdef CID(Durability.create)
static Term mc_create_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  if (io_nul(w->data, w->size)) {
    w->code = EILSEQ;
    return mc_create_pack(e, w);
  }
  return io_work(w, mc_create_call, mc_create_pack);
}
static void __attribute__((constructor)) mc_create_use(void) {
  io_eff(CID(Durability.create), mc_create_run, 0);
}
#endif

static void mc_sync_call(IoWork* w) {
  int fd = (int)w->hand;
  int status;
  do { status = fsync(fd); } while (status < 0 && errno == EINTR);
#ifdef __APPLE__
  if (status == 0) {
    do { status = fcntl(fd, F_FULLFSYNC); } while (status < 0 && errno == EINTR);
  }
#endif
  io_sys_end(w, status);
}
static Term mc_sync_pack(Env e, IoWork* w) {
  return io_tup(e, io_hand(w->hand), io_res(e, w, term_pak(CID(Unit), 0)));
}
#ifdef CID(Durability.sync)
static Term mc_sync_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  return io_work(w, mc_sync_call, mc_sync_pack);
}
static void __attribute__((constructor)) mc_sync_use(void) {
  io_eff(CID(Durability.sync), mc_sync_run, 0);
}
#endif

// Two NUL-terminated paths are packed into one owned work allocation.
static Term mc_path_result(Env e, IoWork* w) {
  free(w->data);
  return io_res(e, w, term_pak(CID(Unit), 0));
}
static void mc_replace_call(IoWork* w) {
  io_sys_end(w, rename(w->data, w->data + w->size + 1));
}
#ifdef CID(Durability.replace)
static Term mc_replace_run(Env e, Term* f, IoWork* w) {
  uint64_t source_size = 0, destination_size = 0;
  char* source = io_cstr(e, f[0], &source_size);
  char* destination = io_cstr(e, f[1], &destination_size);
  w->code = (io_nul(source, source_size) || io_nul(destination, destination_size)) ? EILSEQ : 0;
  w->size = source_size;
  w->data = io_mem(malloc(source_size + destination_size + 2));
  memcpy(w->data, source, source_size + 1);
  memcpy(w->data + source_size + 1, destination, destination_size + 1);
  free(source);
  free(destination);
  return w->code ? mc_path_result(e, w) : io_work(w, mc_replace_call, mc_path_result);
}
static void __attribute__((constructor)) mc_replace_use(void) {
  io_eff(CID(Durability.replace), mc_replace_run, 0);
}
#endif

static void mc_directory_call(IoWork* w) {
  int fd = open(w->data, O_RDONLY | O_DIRECTORY);
  if (fd < 0) { io_sys_end(w, -1); return; }
  int status;
  do { status = fsync(fd); } while (status < 0 && errno == EINTR);
  int saved = errno;
  close(fd);
  errno = saved;
  io_sys_end(w, status);
}
#ifdef CID(Durability.sync_directory)
static Term mc_directory_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  if (io_nul(w->data, w->size)) { w->code = EILSEQ; return mc_path_result(e, w); }
  return io_work(w, mc_directory_call, mc_path_result);
}
static void __attribute__((constructor)) mc_directory_use(void) {
  io_eff(CID(Durability.sync_directory), mc_directory_run, 0);
}
#endif

static void mc_remove_call(IoWork* w) { io_sys_end(w, unlink(w->data)); }
#ifdef CID(Durability.remove)
static Term mc_remove_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  if (io_nul(w->data, w->size)) { w->code = EILSEQ; return mc_path_result(e, w); }
  return io_work(w, mc_remove_call, mc_path_result);
}
static void __attribute__((constructor)) mc_remove_use(void) {
  io_eff(CID(Durability.remove), mc_remove_run, 0);
}
#endif
