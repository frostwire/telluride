/*
 * Telluride macOS launcher.
 *
 * Copyright 2020-2026 FrostWire LLC. Licensed under Apache 2.0.
 *
 * A tiny native executable that fills the role of the old
 * PyInstaller --onefile binary: FrostWire (FrostWireUtils) and the
 * installers look for a single executable file named
 * telluride_macos.<arch>, and this is that file. It simply execs
 * the PyInstaller --onedir bundle that sits next to it
 * (telluride_macos.<arch>.dir/telluride).
 *
 * Why not --onefile itself? A --onefile binary re-extracts into a
 * fresh random _MEIxxxxxx temp folder on every launch, and macOS
 * re-validates the code signature of every Mach-O it loads from
 * that new path (~8s per invocation for telluride, re-checked
 * every time). The --onedir folder is already signed on disk, so
 * macOS validates it once and caches it: ~0.25s warm, the same
 * as running `python3 telluride.py`. Linux/Windows keep
 * --onefile, which has no such per-file trust check there.
 *
 * The launcher is native (not a shell script) so the file
 * FrostWire launches is a real Mach-O of the correct
 * architecture, signable and notarizable like any other binary.
 * execv replaces this process, so exit codes, signals and
 * stdio are passed through unchanged.
 */
#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int try_exec(const char *candidate, int argc, char **argv) {
  if (access(candidate, X_OK) != 0) {
    return -1;
  }
  char **target_argv = malloc(sizeof(char *) * (argc + 1));
  if (target_argv == NULL) {
    return -1;
  }
  target_argv[0] = (char *)candidate;
  for (int i = 1; i < argc; i++) {
    target_argv[i] = argv[i];
  }
  target_argv[argc] = NULL;
  execv(candidate, target_argv);
  /* Only returns on failure. */
  fprintf(stderr, "telluride: failed to execute %s: %s\n", candidate,
          strerror(errno));
  free(target_argv);
  return -1;
}

int main(int argc, char **argv) {
  char exe_path[PATH_MAX];
  uint32_t exe_size = sizeof(exe_path);
  if (_NSGetExecutablePath(exe_path, &exe_size) != 0) {
    fprintf(stderr, "telluride: cannot determine executable path\n");
    return 127;
  }
  char resolved[PATH_MAX];
  if (realpath(exe_path, resolved) == NULL) {
    fprintf(stderr, "telluride: cannot resolve executable path: %s\n",
            strerror(errno));
    return 127;
  }
  char dir_copy[PATH_MAX];
  strncpy(dir_copy, resolved, sizeof(dir_copy) - 1);
  dir_copy[sizeof(dir_copy) - 1] = '\0';
  char *dir = dirname(dir_copy);
  const char *base = strrchr(resolved, '/');
  base = (base != NULL) ? base + 1 : resolved;

  /* Candidates, in order: the --onedir folder shipped with this
   * launcher, then a plain telluride/ folder. */
  char candidate[PATH_MAX];
  snprintf(candidate, sizeof(candidate), "%s/%s.dir/telluride", dir, base);
  if (try_exec(candidate, argc, argv) == 0) {
    return 0; /* Unreachable: try_exec only returns on failure. */
  }
  if (errno != ENOENT && errno != ENOTDIR && errno != EACCES) {
    return 127;
  }
  snprintf(candidate, sizeof(candidate), "%s/telluride/telluride", dir);
  if (try_exec(candidate, argc, argv) == 0) {
    return 0;
  }
  fprintf(stderr,
          "telluride: cannot find the telluride bundle next to %s "
          "(expected %s/%s.dir/telluride)\n",
          resolved, dir, base);
  return 127;
}
