#!/usr/bin/env python3
r"""Exercise Native.policy and NativeHost on macOS, using only authored fixtures.

Usage: python3 Flashback/check-native-sandbox.py [--host /path/to/NativeHost]
       [--dos-app /path/to/DOSBox\ Staging.app] [--scummvm-app /path/to/ScummVM.app]
       [--windows]

Without runtime arguments, use vendor copies in a temporary directory with no
quarantine attributes, as the app build does. --windows also opens and closes
each engine's empty UI and requires READY from an actual on-screen window.
No games are downloaded, and no user source/configuration files are modified.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import signal
import socket
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
PROBE = r'''
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <CoreServices/CoreServices.h>
extern char **environ;
static int failures = 0;
static void check(int good, const char *name) {
    fprintf(stderr, "%s %s\n", good ? "PASS" : "FAIL", name);
    if (!good) failures++;
}
static int denied(int result) { return result < 0 && (errno == EPERM || errno == EACCES); }
static void read_test(const char *path, int allowed, const char *name) {
    int fd = open(path, O_RDONLY);
    check(allowed ? fd >= 0 : denied(fd), name);
    if (fd >= 0) close(fd);
}
static void write_test(const char *path, int allowed, const char *name) {
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    check(allowed ? fd >= 0 : denied(fd), name);
    if (fd >= 0) { write(fd, "x", 1); close(fd); }
}
int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--self-child") == 0) return 97;
    if (argc == 2 && strcmp(argv[1], "--hold") == 0) {
        signal(SIGTERM, SIG_IGN); fprintf(stderr, "HOLDING\n"); fflush(stderr);
        for (;;) pause();
    }
    if (argc != 12) return 2;
    read_test(argv[1], 1, "source read");
    write_test(argv[1], 0, "source write denied");
    write_test(argv[2], 1, "save write");
    read_test(argv[2], 1, "save read");
    read_test(argv[3], 0, "outside file read denied");
    write_test(argv[3], 0, "outside file write denied");
    read_test(argv[4], 0, "source symlink escape denied");
    write_test(argv[5], 0, "save symlink escape denied");
    read_test(argv[6], 0, "Data-volume alias read denied");
    int fd = open(argv[1], O_RDONLY);
    void *mapped = mmap(NULL, 4096, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
    check(mapped == MAP_FAILED && (errno == EPERM || errno == EACCES), "source executable mapping denied");
    if (mapped != MAP_FAILED) munmap(mapped, 4096);
    if (fd >= 0) close(fd);
    pid_t forked = fork();
    if (forked == 0) _exit(0);
    check(denied(forked), "fork denied");
    if (forked > 0) waitpid(forked, NULL, 0);
    pid_t spawned = -1; char *args[] = {"/bin/sh", "-c", "exit 0", NULL};
    int status = posix_spawn(&spawned, args[0], NULL, NULL, args, environ);
    check(status == EPERM || status == EACCES, "outside executable denied");
    if (status == 0) waitpid(spawned, NULL, 0);
    char *self_args[] = {argv[0], "--self-child", NULL};
    status = posix_spawn(&spawned, argv[0], NULL, NULL, self_args, environ);
    check(status == EPERM || status == EACCES, "runtime self-spawn denied");
    if (status == 0) waitpid(spawned, NULL, 0);
    struct sockaddr_in address = {0}; address.sin_family = AF_INET;
    address.sin_port = htons(atoi(argv[7])); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int net = socket(AF_INET, SOCK_STREAM, 0);
    int connected = net < 0 ? -1 : connect(net, (void *)&address, sizeof(address));
    check(denied(connected), "TCP outbound denied");
    if (net >= 0) close(net);
    net = socket(AF_INET, SOCK_DGRAM, 0);
    int sent = net < 0 ? -1 : (int)sendto(net, "x", 1, 0, (void *)&address, sizeof(address));
    check(denied(sent), "UDP outbound denied");
    if (net >= 0) close(net);
    net = socket(AF_INET, SOCK_STREAM, 0); address.sin_port = 0;
    int bound = net < 0 ? -1 : bind(net, (void *)&address, sizeof(address));
    check(denied(bound), "TCP listener denied");
    if (net >= 0) close(net);
    CFURLRef app = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)argv[8], strlen(argv[8]), true);
    OSStatus opened = LSOpenCFURLRef(app, NULL);
    check(opened != noErr, "LaunchServices app launch denied"); CFRelease(app);
    read_test(argv[9], 0, "other game data denied");
    write_test(argv[10], 0, "other game saves denied");
    char *cwd = getcwd(NULL, 0); check(cwd && strcmp(cwd, argv[11]) == 0, "private working directory");
    free(cwd);
    execv(argv[0], self_args);
    check(errno == EPERM || errno == EACCES, "runtime self-exec denied");
    return failures ? 1 : 0;
}
'''


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(cmd, **kwargs):
    return subprocess.run([str(x) for x in cmd], check=True, capture_output=True, text=True, **kwargs)


def host_command(host, runtime, executable, game, saves, *args):
    return [str(host), "--profile", str(HERE / "Native.policy"), "--runtime", str(runtime),
            "--executable", str(executable), "--game", str(game), "--saves", str(saves), "--", *map(str, args)]


def supervised(command, timeout=15, window=False):
    # Keep stdin's writer open. communicate() would close it before completion.
    with tempfile.TemporaryFile() as log:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True)
        try:
            process.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            timed_out = True
            process.stdin.close()
            process.stdin = None
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
        output = process.stdout.read()
        log.seek(0)
        error = log.read().decode(errors="replace")
        if window:
            require(timed_out and "READY\t" in output and process.returncode in (0, 143),
                    f"Window/start-stop test failed: {output}\n{error[-4000:]}")
        else:
            require(not timed_out and process.returncode == 0, f"Sandbox command failed: {output}\n{error[-6000:]}")
        return output, error


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def shutdown_test(command):
    # The intermediary owns the stdin writer, like Flashback. Kill it without
    # cleanup: the supervisor must observe EOF, force-kill a TERM-ignoring child,
    # and reap it. Its stdout reader also disappears, exercising broken pipes.
    code = """
import json, os, subprocess, sys, time
p = subprocess.Popen(json.loads(sys.argv[1]), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
line = p.stdout.readline()
while p.stderr.readline().strip() != 'HOLDING':
    if p.poll() is not None: raise SystemExit('probe exited early')
print(str(p.pid) + ' ' + line.split('\\t')[1].strip(), flush=True)
time.sleep(30)
"""
    actor = subprocess.Popen([sys.executable, "-c", code, json.dumps(command)], stdout=subprocess.PIPE, text=True)
    try:
        import select
        require(bool(select.select([actor.stdout], [], [], 10)[0]), "Lifecycle fixture did not start")
        helper_pid, child_pid = map(int, actor.stdout.readline().split())
        actor.kill()
        actor.wait(timeout=3)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and (alive(child_pid) or alive(helper_pid)):
            time.sleep(0.05)
        require(not alive(child_pid) and not alive(helper_pid), "Native process survived abrupt parent shutdown")
    finally:
        if actor.poll() is None:
            actor.kill()
        actor.wait()
    print("PASS abrupt parent shutdown and forced child termination")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path)
    parser.add_argument("--dos-app", type=Path)
    parser.add_argument("--scummvm-app", type=Path)
    parser.add_argument("--windows", action="store_true")
    options = parser.parse_args()
    require(sys.platform == "darwin", "Native sandbox checks require macOS")
    with tempfile.TemporaryDirectory(prefix="flashback-native-check-") as scratch:
        temp = Path(scratch).resolve()
        host = options.host
        if host is None:
            host = temp / "NativeHost"
            run(["xcrun", "swiftc", "-target", f"{platform.machine()}-apple-macos13", "-O", HERE / "NativeHost.swift", "-o", host])
        game, saves, outside = (temp / name for name in ("game", "saves", "outside"))
        for path in [game, saves, outside]:
            path.mkdir()
        source = game / "source.dat"
        source.write_bytes(b"authored fixture" + b"\0" * 4096)
        private = outside / "private.txt"
        private.write_text("private fixture")
        (game / "escape").symlink_to(private)
        (saves / "escape").symlink_to(private)
        other_game = outside / "other-game.dat"
        other_game.write_text("other game")
        runtime = temp / "Probe.app"
        executable = runtime / "Contents/MacOS/dosbox"
        executable.parent.mkdir(parents=True)
        c_file = temp / "probe.c"
        c_file.write_text(PROBE)
        run(["xcrun", "clang", "-Wno-deprecated-declarations", c_file, "-framework", "CoreServices", "-o", executable])
        escape_app = game / "Escape.app"
        escape_binary = escape_app / "Contents/MacOS/escape"
        escape_binary.parent.mkdir(parents=True)
        marker = outside / "launchservices-escaped"
        payload = temp / "escape.c"
        payload.write_text('#include <fcntl.h>\n#include <unistd.h>\nint main(void) { int fd=open(' + json.dumps(str(marker)) + ',O_CREAT|O_WRONLY,0600);if(fd>=0)close(fd);return 0;}\n')
        run(["xcrun", "clang", payload, "-o", escape_binary])
        import plistlib
        (escape_app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "escape", "CFBundleIdentifier": "org.flashback.sandbox-fixture", "CFBundlePackageType": "APPL"}))
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            command = host_command(host, runtime, executable, game, saves, source, saves / "save.dat", private,
                                   game / "escape", saves / "escape", "/System/Volumes/Data" + str(private),
                                   listener.getsockname()[1], escape_app, other_game, outside / "other-game-save", saves)
            output, error = supervised(command)
        require("READY\t" not in output, "Headless probe falsely reported READY")
        require(not marker.exists(), "LaunchServices escaped the sandbox")
        require(private.read_text() == "private fixture", "Outside fixture was modified")
        print(error.strip())
        shutdown_test(host_command(host, runtime, executable, game, saves, "--hold"))
        run(["/usr/bin/xattr", "-w", "com.apple.quarantine", "0083;00000000;FlashbackProbe;", runtime])
        quarantined = subprocess.run(host_command(host, runtime, executable, game, saves, "--hold"), input="", capture_output=True, text=True)
        require(quarantined.returncode != 0 and "STARTED\t" not in quarantined.stdout and "quarantined" in quarantined.stdout, "Quarantined runtime was not rejected")
        print("PASS quarantined runtime rejected before execution")
        for label, provided, vendor, engine in [
            ("DOSBox Staging", options.dos_app, "dosbox-staging/DOSBox Staging.app", "dosbox"),
            ("ScummVM", options.scummvm_app, "scummvm/ScummVM.app", "scummvm")]:
            app = provided
            if app is None:
                original = HERE.parent / "vendor" / vendor
                require(original.exists(), f"Missing {original}; pass its built runtime with the command-line option")
                app = temp / original.name
                run(["/usr/bin/ditto", "--noextattr", "--noqtn", original, app])
            app = app.resolve()
            binary = app / "Contents/MacOS" / engine
            version_args = ["--version"]
            if engine == "scummvm":
                version_args.insert(0, "--config=" + str(saves / "scummvm.ini"))
            _, error = supervised(host_command(host, app, binary, game, saves, *version_args))
            require(label.lower().replace(" ", "-") in error.lower(), f"Missing {label} version output")
            print(f"PASS {label} sandboxed version")
            if engine == "scummvm":
                _, error = supervised(host_command(host, app, binary, game, saves,
                    "--config=" + str(saves / "scummvm.ini"), "--path=" + str(game), "--game=director", "--detect"))
                require("could not find any game" in error.lower(), "Director detector did not reject the authored non-game fixture")
                print("PASS Director detector on authored non-game directory")
            if options.windows:
                args = ["--noprimaryconf", "--nolocalconf", "--set", "midi.mididevice=none"] if engine == "dosbox" else ["--config=" + str(saves / "scummvm.ini")]
                supervised(host_command(host, app, binary, game, saves, *args), timeout=5, window=True)
                print(f"PASS {label} real window readiness and stdin-EOF shutdown")
    print("All native sandbox checks passed.")


if __name__ == "__main__":
    main()
