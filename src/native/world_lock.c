// OS-only, nonblocking BSD advisory lock. No save-format interpretation.
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

static void mc_world_lease_call(IoWork* w) {
  int fd;
  do {
    fd = open(w->data, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) { io_sys_end(w, -1); return; }
  struct stat status;
  int checked;
  do { checked = fstat(fd, &status); } while (checked < 0 && errno == EINTR);
  if (checked < 0 || !S_ISREG(status.st_mode)) {
    int saved = checked < 0 ? errno : EINVAL;
    close(fd);
    errno = saved;
    io_sys_end(w, -1);
    return;
  }
  int locked;
  do { locked = flock(fd, LOCK_EX | LOCK_NB); } while (locked < 0 && errno == EINTR);
  if (locked < 0) {
    int saved = errno;
    close(fd);
    errno = saved;
    io_sys_end(w, -1);
    return;
  }
  w->made = (intptr_t)io_sys_end(w, fd);
}

static Term mc_world_lease_pack(Env e, IoWork* w) {
  free(w->data);
  return io_res(e, w, io_hand(w->made));
}

#ifdef CID(Native.acquire)
static Term mc_world_lease_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  if (io_nul(w->data, w->size)) {
    w->code = EILSEQ;
    return mc_world_lease_pack(e, w);
  }
  return io_work(w, mc_world_lease_call, mc_world_lease_pack);
}
static void __attribute__((constructor)) mc_world_lease_use(void) {
  io_eff(CID(Native.acquire), mc_world_lease_run, 0);
}
#endif

static void mc_world_release_call(IoWork* w) {
  // Do not retry close on EINTR: the descriptor's state can be ambiguous.
  io_sys_end(w, close((int)w->hand));
}

static Term mc_world_release_pack(Env e, IoWork* w) {
  return io_res(e, w, term_pak(CID(Unit), 0));
}

#ifdef CID(Native.release)
static Term mc_world_release_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  return io_work(w, mc_world_release_call, mc_world_release_pack);
}
static void __attribute__((constructor)) mc_world_release_use(void) {
  io_eff(CID(Native.release), mc_world_release_run, 0);
}
#endif
