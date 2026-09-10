#include <mach-o/dyld.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    char raw[PATH_MAX], path[PATH_MAX], resources[PATH_MAX], runtime[PATH_MAX];
    char movie[PATH_MAX], base[PATH_MAX];
    uint32_t size = sizeof(raw);
    if (_NSGetExecutablePath(raw, &size) || !realpath(raw, path)) return 1;
    char *contents = dirname(dirname(path));
    snprintf(resources, sizeof(resources), "%s/Resources/game", contents);
    snprintf(runtime, sizeof(runtime), "%s/Frameworks/Ruffle.app/Contents/MacOS/ruffle", contents);
    snprintf(movie, sizeof(movie), "%s/root/game.swf", resources);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (UInt8 *)resources, strlen(resources), true);
    if (!url || !CFStringGetCString(CFURLGetString(url), base, sizeof(base), kCFStringEncodingUTF8)) return 1;
    CFRelease(url);
    if (chdir(resources)) { perror("Game resources"); return 1; }
    execl(runtime, runtime, movie, "--base", base, "--width", "960", "--height", "720",
          "--filesystem-access-mode", "allow", "--open-url-mode", "confirm", "--no-gui", NULL);
    perror("Unable to start Ruffle");
    return 1;
}
