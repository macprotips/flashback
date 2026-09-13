#!/usr/bin/env python3
import os, selectors, subprocess, sys, time
jdk, host, game, saves, policy, runner = sys.argv[1:]
def cmd(entry):
    return [jdk + "/bin/java", "-Djava.security.manager", "-Djava.security.policy==" + policy, "-Dflashback.runner=" + runner, "-Dflashback.game=" + game, "-Duser.home=" + saves, "-cp", host, "JavaRunner", "--play", entry]
def wait_ready(p, timeout):
    end=time.monotonic()+timeout; data=b""
    with selectors.DefaultSelector() as ready:
        ready.register(p.stdout,selectors.EVENT_READ)
        while time.monotonic()<end:
            if not ready.select(max(0,end-time.monotonic())): break
            chunk=os.read(p.stdout.fileno(),65536)
            if not chunk: break
            data+=chunk
            if b"FLASHBACK_READY\n" in data: return [data.decode(errors="replace")],True
    if p.poll() is None:
        p.kill(); p.wait(timeout=5)
    return [data.decode(errors="replace")],False
p=subprocess.Popen(cmd(game+"/applet.jnlp"),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
lines, ready=wait_ready(p,12)
if not ready: raise SystemExit("FAIL: applet did not announce readiness: "+"".join(lines))
p.stdin.close()
if p.wait(timeout=8)!=0: raise SystemExit("FAIL: applet did not exit after parent EOF")
if open(os.path.join(saves,"applet.txt")).read()!="init,start,stop,destroy,": raise SystemExit("FAIL: parent EOF did not stop/destroy applet")
p=subprocess.Popen(cmd(game+"/fail-applet.jnlp"),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
lines, ready=wait_ready(p,8)
if ready or p.wait(timeout=8)==0: raise SystemExit("FAIL: failing applet announced readiness or exited successfully: "+"".join(lines))
print("PASS: subprocess readiness follows init, parent EOF destroys applet, failed init never readies")
