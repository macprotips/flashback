// SPDX-License-Identifier: GPL-3.0-only
import java.io.*;
import java.nio.file.*;
import java.security.Permission;
import java.util.PropertyPermission;

/** Deliberately loaded as game code, without the host's permissions. */
public final class JavaPolicyCheck {
    static void denied(Permission permission) {
        try { System.getSecurityManager().checkPermission(permission); }
        catch (SecurityException expected) { return; }
        throw new AssertionError("Unexpected permission: " + permission);
    }
    public static void main(String[] args) throws Exception {
        if (System.getSecurityManager() == null) throw new AssertionError("No security manager");
        Path save = Paths.get(System.getProperty("user.home"),"check-save.txt");
        Files.write(save,"saved".getBytes("UTF-8"));
        if (!new String(Files.readAllBytes(save),"UTF-8").equals("saved")) throw new AssertionError("Save read/write failed");
        denied(new FilePermission("/private/flashback-outside-check","read,write"));
        denied(new FilePermission("/usr/bin/true","execute"));
        denied(new java.net.SocketPermission("127.0.0.1:9","connect"));
        denied(new java.net.SocketPermission("localhost:9000","listen"));
        denied(new RuntimePermission("setSecurityManager"));
        denied(new RuntimePermission("createClassLoader"));
        denied(new RuntimePermission("loadLibrary.test"));
        denied(new java.lang.reflect.ReflectPermission("suppressAccessChecks"));
        denied(new PropertyPermission("user.home","write"));
        System.out.println("PASS: Java save read/write; blocked external files, process execution, networking, native code, reflection, policy replacement, and property changes");
    }
}
