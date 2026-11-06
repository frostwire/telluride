/*
 * Telluride macOS launcher.
 *
 * Copyright 2020-2026 FrostWire LLC. Licensed under Apache 2.0.
 *
 * telluride_macos.<arch> is a single native executable, the file
 * FrostWire (FrostWireUtils) and the installers look for and the file
 * frostwire.com distributes. It carries the signed PyInstaller --onedir
 * bundle inside itself, as a zip in the __TELLURIDE,__payload section
 * (linked in by macos_launcher.sh, so the code signature covers it).
 *
 * The first run unpacks that bundle once into
 *   ~/Library/Caches/com.frostwire.Telluride/<build>-<arch>-<hash>/
 * and every run execs the unpacked telluride from there.
 *
 * Why not PyInstaller --onefile? A --onefile binary re-extracts into a
 * fresh random _MEIxxxxxx temp folder on every launch, and macOS
 * re-validates the code signature of every Mach-O it loads from that
 * new path (~8s per invocation for telluride, every time). Unpacking
 * once to a fixed path lets macOS validate the bundle once and cache
 * it: ~0.1s warm, the same as running `python3 telluride.py`.
 * Linux/Windows keep --onefile, which has no such per-file check.
 *
 * The unpack is atomic: it goes to a private temp folder next to its
 * final place and is renamed into place with a completion marker
 * inside, so concurrent first runs never see a half-written bundle.
 * Other versions are removed once they have not been used for a week.
 * Nothing is printed to stdout (FrostWire parses telluride's output);
 * errors go to stderr. execv replaces this process, so exit codes,
 * signals and stdio pass through unchanged.
 *
 * A launcher built without a payload (development) execs the --onedir
 * folder next to it instead: telluride_macos.<arch>.dir/telluride.
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/ldsyms.h>
#include <pwd.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#ifndef TELLURIDE_PAYLOAD_ID
#define TELLURIDE_PAYLOAD_ID ""
#endif

#define PAYLOAD_SEGMENT "__TELLURIDE"
#define PAYLOAD_SECTION "__payload"
#define CACHE_SUBDIR "Library/Caches/com.frostwire.Telluride"
#define COMPLETE_MARKER ".complete"
#define TEMP_PREFIX ".tmp-"
#define STALE_VERSION_SECONDS (7 * 24 * 60 * 60)
#define STALE_TEMP_SECONDS (60 * 60)

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
  int saved = errno;
  fprintf(stderr, "telluride: failed to execute %s: %s\n", candidate,
          strerror(saved));
  free(target_argv);
  errno = saved;
  return -1;
}

/* Runs a system tool with stdout discarded; returns its exit status. */
static int run_quiet(char *const tool_argv[]) {
  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init(&actions) != 0) {
    return -1;
  }
  posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null",
                                   O_WRONLY, 0);
  pid_t pid;
  int rc = posix_spawn(&pid, tool_argv[0], &actions, NULL, tool_argv,
                       environ);
  posix_spawn_file_actions_destroy(&actions);
  if (rc != 0) {
    fprintf(stderr, "telluride: cannot run %s: %s\n", tool_argv[0],
            strerror(rc));
    return -1;
  }
  int status;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) {
      return -1;
    }
  }
  return (WIFEXITED(status)) ? WEXITSTATUS(status) : -1;
}

static void remove_tree(const char *path) {
  char *const rm_argv[] = {"/bin/rm", "-rf", (char *)path, NULL};
  run_quiet(rm_argv);
}

/* mkdir -p with mode 0700 for the folders it creates. */
static int make_dirs(const char *path) {
  char buf[PATH_MAX];
  if (snprintf(buf, sizeof(buf), "%s", path) >= (int)sizeof(buf)) {
    return -1;
  }
  for (char *p = buf + 1; *p != '\0'; p++) {
    if (*p == '/') {
      *p = '\0';
      if (mkdir(buf, 0700) != 0 && errno != EEXIST) {
        return -1;
      }
      *p = '/';
    }
  }
  if (mkdir(buf, 0700) != 0 && errno != EEXIST) {
    return -1;
  }
  return 0;
}

/* The cache root must be a real folder owned by this user. */
static int check_cache_root(const char *root) {
  struct stat st;
  if (lstat(root, &st) != 0) {
    return -1;
  }
  if (!S_ISDIR(st.st_mode) || st.st_uid != getuid()) {
    fprintf(stderr,
            "telluride: %s is not a folder owned by the current user\n",
            root);
    return -1;
  }
  return 0;
}

/* Build ids are made by macos_launcher.sh: <build>-<arch>-<hash>. */
static int is_safe_id(const char *id) {
  if (id[0] == '\0' || id[0] == '.') {
    return 0;
  }
  for (const char *p = id; *p != '\0'; p++) {
    char c = *p;
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') || c == '-' || c == '_' || c == '.')) {
      return 0;
    }
  }
  return 1;
}

static int write_file(const char *path, const void *data, size_t size) {
  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (fd < 0) {
    return -1;
  }
  const char *p = data;
  while (size > 0) {
    ssize_t n = write(fd, p, size);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      close(fd);
      return -1;
    }
    p += n;
    size -= (size_t)n;
  }
  return close(fd);
}

/* Unpacked, and the executable and its libraries are still there. */
static int is_complete(const char *version_dir) {
  char marker[PATH_MAX];
  char exe[PATH_MAX];
  char libs[PATH_MAX];
  snprintf(marker, sizeof(marker), "%s/%s", version_dir, COMPLETE_MARKER);
  snprintf(exe, sizeof(exe), "%s/telluride", version_dir);
  snprintf(libs, sizeof(libs), "%s/_internal/base_library.zip", version_dir);
  return access(marker, F_OK) == 0 && access(exe, X_OK) == 0 &&
         access(libs, F_OK) == 0;
}

/* Unpacks the payload into <root>/<id>; 0 when it is ready to run. */
static int unpack(const char *root, const char *id, const void *payload,
                  size_t payload_size) {
  char target[PATH_MAX];
  char temp[PATH_MAX];
  char zip[PATH_MAX];
  char marker[PATH_MAX];
  snprintf(target, sizeof(target), "%s/%s", root, id);
  snprintf(temp, sizeof(temp), "%s/%s%s-XXXXXX", root, TEMP_PREFIX, id);
  if (mkdtemp(temp) == NULL) {
    fprintf(stderr, "telluride: cannot create a folder in %s: %s\n", root,
            strerror(errno));
    return -1;
  }
  snprintf(zip, sizeof(zip), "%s/.payload.zip", temp);
  if (write_file(zip, payload, payload_size) != 0) {
    fprintf(stderr, "telluride: cannot write %s: %s\n", zip,
            strerror(errno));
    remove_tree(temp);
    return -1;
  }
  /* ditto keeps symlinks (Python.framework needs them) and embedded
   * code signatures; --noqtn: these files come from the signed,
   * notarized launcher, not from a download. */
  char *const ditto_argv[] = {"/usr/bin/ditto", "-x", "-k", "--noqtn",
                              zip, temp, NULL};
  int rc = run_quiet(ditto_argv);
  unlink(zip);
  snprintf(marker, sizeof(marker), "%s/%s", temp, COMPLETE_MARKER);
  if (rc != 0 || write_file(marker, "", 0) != 0) {
    fprintf(stderr, "telluride: cannot unpack the telluride bundle into %s\n",
            temp);
    remove_tree(temp);
    return -1;
  }
  if (rename(temp, target) == 0) {
    return 0;
  }
  if (is_complete(target)) {
    /* Another first run won the race; use its copy. */
    remove_tree(temp);
    return 0;
  }
  /* An incomplete copy is in the way (files deleted from the cache):
   * replace it. */
  remove_tree(target);
  if (rename(temp, target) == 0 || is_complete(target)) {
    remove_tree(temp);
    return 0;
  }
  fprintf(stderr, "telluride: cannot move the bundle to %s: %s\n", target,
          strerror(errno));
  remove_tree(temp);
  return -1;
}

/* Removes other versions unused for a week and abandoned temp folders. */
static void remove_stale(const char *root, const char *id) {
  DIR *dir = opendir(root);
  if (dir == NULL) {
    return;
  }
  time_t now = time(NULL);
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    const char *name = entry->d_name;
    if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0 ||
        strcmp(name, id) == 0) {
      continue;
    }
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s", root, name);
    struct stat st;
    if (strncmp(name, TEMP_PREFIX, strlen(TEMP_PREFIX)) == 0) {
      if (lstat(path, &st) == 0 && now - st.st_mtime > STALE_TEMP_SECONDS) {
        remove_tree(path);
      }
      continue;
    }
    char marker[PATH_MAX];
    snprintf(marker, sizeof(marker), "%s/%s", path, COMPLETE_MARKER);
    if (stat(marker, &st) != 0 || now - st.st_mtime > STALE_VERSION_SECONDS) {
      remove_tree(path);
    }
  }
  closedir(dir);
}

static const char *home_dir(void) {
  const char *home = getenv("HOME");
  if (home != NULL && home[0] == '/') {
    return home;
  }
  struct passwd *pw = getpwuid(getuid());
  return (pw != NULL) ? pw->pw_dir : NULL;
}

static int run_embedded(const void *payload, size_t payload_size, int argc,
                        char **argv) {
  const char *id = TELLURIDE_PAYLOAD_ID;
  if (!is_safe_id(id)) {
    fprintf(stderr, "telluride: invalid embedded bundle id '%s'\n", id);
    return 127;
  }
  const char *home = home_dir();
  if (home == NULL) {
    fprintf(stderr, "telluride: cannot determine the home folder\n");
    return 127;
  }
  char root[PATH_MAX];
  char version_dir[PATH_MAX];
  char exe[PATH_MAX];
  char marker[PATH_MAX];
  snprintf(root, sizeof(root), "%s/%s", home, CACHE_SUBDIR);
  snprintf(version_dir, sizeof(version_dir), "%s/%s", root, id);
  snprintf(exe, sizeof(exe), "%s/telluride", version_dir);
  snprintf(marker, sizeof(marker), "%s/%s", version_dir, COMPLETE_MARKER);

  if (is_complete(version_dir)) {
    utimes(marker, NULL); /* Last use, for remove_stale. */
    try_exec(exe, argc, argv);
    /* Only returns if the cached copy cannot run: mark it incomplete
     * so unpack replaces it. */
    unlink(marker);
  }
  if (make_dirs(root) != 0) {
    fprintf(stderr, "telluride: cannot create %s: %s\n", root,
            strerror(errno));
    return 127;
  }
  if (check_cache_root(root) != 0) {
    return 127;
  }
  if (unpack(root, id, payload, payload_size) != 0) {
    return 127;
  }
  remove_stale(root, id);
  try_exec(exe, argc, argv);
  return 127;
}

/* Development launcher: exec the --onedir folder next to this file. */
static int run_adjacent(int argc, char **argv) {
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
  snprintf(dir_copy, sizeof(dir_copy), "%s", resolved);
  const char *dir = dirname(dir_copy);
  const char *base = strrchr(resolved, '/');
  base = (base != NULL) ? base + 1 : resolved;

  char candidate[PATH_MAX];
  snprintf(candidate, sizeof(candidate), "%s/%s.dir/telluride", dir, base);
  try_exec(candidate, argc, argv);
  fprintf(stderr,
          "telluride: this launcher has no embedded bundle and none was "
          "found next to it (expected %s)\n",
          candidate);
  return 127;
}

int main(int argc, char **argv) {
  unsigned long payload_size = 0;
  const uint8_t *payload = getsectiondata(
      &_mh_execute_header, PAYLOAD_SEGMENT, PAYLOAD_SECTION, &payload_size);
  if (payload != NULL && payload_size > 0) {
    return run_embedded(payload, payload_size, argc, argv);
  }
  return run_adjacent(argc, argv);
}
