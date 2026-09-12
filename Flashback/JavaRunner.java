// SPDX-License-Identifier: GPL-3.0-only
import java.awt.*;
import java.io.*;
import java.lang.reflect.*;
import java.net.*;
import java.util.jar.*;

/** A small, separately sandboxed host for ordinary Java game applications. */
public final class JavaRunner {
    static Class<?> gameClass;

    static Manifest manifest(File file) throws IOException {
        try (JarFile jar = new JarFile(file)) {
            JarEntry entry = jar.getJarEntry("META-INF/MANIFEST.MF");
            if (entry == null || entry.getSize() < 0 || entry.getSize() > 65536)
                throw new IOException("This JAR needs a valid application manifest (at most 64 KB).");
            try (InputStream stream = jar.getInputStream(entry)) { return new Manifest(stream); }
        }
    }

    /** Classifies a JAR before choosing the desktop or Java ME player. */
    public static String inspect(File file) throws IOException {
        Manifest manifest = manifest(file);
        Attributes attributes = manifest.getMainAttributes();
        if (attributes.getValue("MIDlet-1") != null ||
            attributes.getValue("MicroEdition-Profile") != null ||
            attributes.getValue("MicroEdition-Configuration") != null) return "J2ME";
        String name = attributes.getValue(Attributes.Name.MAIN_CLASS);
        if (name == null || !name.matches("[A-Za-z_$][A-Za-z0-9_$]*(\\.[A-Za-z_$][A-Za-z0-9_$]*)*"))
            throw new IOException("This is not a standalone Java game. Use a runnable JAR with a Main-Class or a Java ME JAR with a MIDlet manifest.");
        try (JarFile jar = new JarFile(file)) {
            if (jar.getJarEntry(name.replace('.', '/') + ".class") == null)
                throw new IOException("The game's main class is missing from this JAR.");
        }
        return "DESKTOP:" + name;
    }

    public static String mainClass(File file) throws IOException {
        String result = inspect(file);
        if (!result.startsWith("DESKTOP:"))
            throw new IOException("This is a Java ME game. Use the bundled J2ME player instead of the desktop Java player.");
        return result.substring("DESKTOP:".length());
    }

    static void launch(File file) throws Exception {
        String name = mainClass(file);
        URLClassLoader loader = new Wiz3Display(file);
        Thread.currentThread().setContextClassLoader(loader);
        gameClass = Class.forName(name, false, loader);
        Method main = gameClass.getMethod("main", String[].class);
        if (!Modifier.isStatic(main.getModifiers()) || main.getReturnType() != Void.TYPE)
            throw new IOException("This JAR does not have a runnable main method.");
        main.invoke(null, (Object)new String[0]);
    }

    public static void paintWiz3(Component component, Graphics graphics, Image image) {
        if (image == null) return;
        Graphics2D canvas = (Graphics2D)graphics.create();
        try {
            canvas.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_NEAREST_NEIGHBOR);
            // The original browser playfield is 480 × 248 inside a 496 × 256 work buffer.
            double scale = Math.min(component.getWidth() / 480.0, component.getHeight() / 248.0);
            int width = (int)Math.round(480 * scale), height = (int)Math.round(248 * scale);
            int x = (component.getWidth() - width) / 2, y = (component.getHeight() - height) / 2;
            canvas.setColor(Color.BLACK);
            canvas.fillRect(0, 0, component.getWidth(), component.getHeight());
            canvas.drawImage(image, x, y, x + width, y + height, 16, 0, 496, 248, component);
        } finally { canvas.dispose(); }
    }

    public static void main(String[] args) {
        try {
            if (args.length != 2) throw new IOException("Choose a Java game from Flashback.");
            File file = new File(args[1]).getCanonicalFile();
            if (args[0].equals("--inspect")) { System.out.println(inspect(file)); return; }
            if (!args[0].equals("--play")) throw new IOException("Unknown player command.");
            Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
                error.printStackTrace();
                System.exit(1);
            });
            Thread parent = new Thread(() -> {
                try { while (System.in.read() != -1) {} } catch (IOException ignored) {}
                System.exit(0);
            }, "Flashback parent connection");
            parent.setDaemon(true);
            parent.start();
            // ponytail: AWT/Swing desktop games only; applet descriptors and JavaFX are separate runtimes.
            Thread monitor = new Thread(() -> {
                boolean[] opened = {false};
                try {
                    for (int second = 0; ; second++) {
                        EventQueue.invokeAndWait(() -> {
                            boolean visible = false;
                            for (Window window : Window.getWindows()) visible |= window.isShowing();
                            if (visible && !opened[0]) {
                                opened[0] = true;
                                System.out.println("FLASHBACK_READY");
                                System.out.flush();
                            } else if (!visible && opened[0]) { System.exit(0); }
                        });
                        if (!opened[0] && second >= 30) throw new IOException("The game did not open a window.");
                        Thread.sleep(1000);
                    }
                } catch (Throwable error) { error.printStackTrace(); System.exit(1); }
            }, "Flashback game monitor");
            monitor.start();
            launch(file);
        } catch (Throwable error) {
            Throwable cause = error instanceof InvocationTargetException ? error.getCause() : error;
            cause.printStackTrace();
            System.exit(1);
        }
    }
}
