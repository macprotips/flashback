// SPDX-License-Identifier: GPL-3.0-only
import java.applet.Applet;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Trusted assertions for JavaRunner's local JNLP and applet boundary. */
public final class JavaFormatChecks {
    private static String text(File file) throws Exception {
        return new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
    }
    private static void expectFailure(File file, String expected) throws Exception {
        try { JavaRunner.launch(file); throw new AssertionError("accepted " + file); }
        catch (Throwable error) {
            String message = String.valueOf(error.getMessage());
            if (!message.contains(expected)) throw new AssertionError("wrong failure: " + message, error);
        }
    }
    public static void main(String[] args) throws Exception {
        File game = new File(args[0]), saves = new File(args[1]);
        File app = new File(game, "app.jnlp"), applet = new File(game, "applet.jnlp");
        if (!"JNLP:APPLICATION".equals(JavaRunner.inspect(app))) throw new AssertionError("application inspect");
        if (!"JNLP:APPLET".equals(JavaRunner.inspect(applet))) throw new AssertionError("applet inspect");
        JavaRunner.launch(app);
        if (!"first arg|sp ace|helper".equals(text(new File(saves, "application.txt")))) throw new AssertionError("arguments/classpath");
        Applet running = JavaRunner.startAppletForCheck(applet);
        JavaRunner.stopAppletForCheck(running);
        if (!"init,start,stop,destroy,".equals(text(new File(saves, "applet.txt")))) throw new AssertionError("applet lifecycle");
        expectFailure(new File(game, "remote.jnlp"), "network URLs are not supported");
        expectFailure(new File(game, "native.jnlp"), "native libraries are not supported");
        expectFailure(new File(game, "escape.jnlp"), "escapes this game's folder");
        expectFailure(new File(game, "properties.jnlp"), "system properties are not supported");
        expectFailure(new File(game, "platform.jnlp"), "Platform-specific JNLP resources");
        expectFailure(new File(game, "host.jnlp"), "must come from");
        try { JavaRunner.launch(new File(game, "fail.jnlp")); throw new AssertionError("failed startup accepted"); }
        catch (java.lang.reflect.InvocationTargetException expected) {
            if (!String.valueOf(expected.getCause()).contains("authored startup failure")) throw expected;
        }
        System.out.println("PASS: JNLP applications/applets, local multi-JAR classpaths, escaped paths, args, lifecycle, shutdown, policy, and rejected extensions");
    }
}
