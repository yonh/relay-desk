/*
 * RelayDeskUpdater launch stub.
 *
 * LaunchServices refuses to start an .app whose CFBundleExecutable is a text
 * script (`open -n` fails with LS error -10669 on macOS 15/26), so the helper
 * bundle ships this tiny Mach-O trampoline as `Contents/MacOS/updater`. It
 * forwards control to the real logic in `Contents/MacOS/updater.sh`, passing
 * through every argv the sandboxed app delivered via
 * `/usr/bin/open -n … --args`.
 *
 * Rebuild after edits:
 *   clang -Os -arch arm64 -arch x86_64 \
 *     -o ../RelayDeskUpdater.app/Contents/MacOS/updater updater_stub.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc < 1 || argv[0] == NULL) return 70; /* EX_OSERR */
    char script[4096];
    int n = snprintf(script, sizeof(script), "%s.sh", argv[0]);
    if (n <= 0 || (size_t)n >= sizeof(script)) return 70;
    /* argv = ["bash", "<self>.sh", original argv[1..argc-1], NULL] */
    char **args = calloc((size_t)argc + 2, sizeof(char *));
    if (args == NULL) return 70;
    args[0] = (char *)"bash";
    args[1] = script;
    for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
    args[argc + 1] = NULL;
    execv("/bin/bash", args);
    return 70; /* execv only returns on failure */
}
