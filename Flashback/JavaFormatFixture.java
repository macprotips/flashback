// SPDX-License-Identifier: GPL-3.0-only
import java.applet.Applet;
import java.io.*;
import java.net.SocketPermission;

/** Small authored game classes used by check-java-formats.sh. */
public final class JavaFormatFixture {
    private static void write(String name, String value) throws Exception {
        File file = new File(System.getProperty("user.home"), name);
        try (Writer out = new OutputStreamWriter(new FileOutputStream(file), "UTF-8")) { out.write(value); }
    }
    public static final class Application {
        public static void main(String[] args) throws Exception {
            InputStream data = Application.class.getResourceAsStream("/fixture data.txt");
            if (data == null || data.read() != 'o') throw new AssertionError("resource path failed");
            write("application.txt", String.join("|", args) + "|" + JavaFormatHelper.value());
        }
    }
    public static final class LifecycleApplet extends Applet {
        private String events = "";
        private void event(String value) { events += value + ","; }
        public void init() {
            event("init");
            if (getWidth()!=320 || getHeight()!=200 || isActive()) throw new AssertionError("initial applet dimensions/state");
            if (!"value with spaces".equals(getParameter("magic"))) throw new AssertionError("applet params failed");
            if (!getCodeBase().toExternalForm().contains("lib%20")) throw new AssertionError("applet codebase failed");
            try { System.getSecurityManager().checkPermission(new SocketPermission("127.0.0.1:9", "connect")); }
            catch (SecurityException expected) { return; }
            throw new AssertionError("applet networking was allowed");
        }
        public void start() { if (!isActive()) throw new AssertionError("inactive start"); event("start"); }
        public void stop() { if (isActive()) throw new AssertionError("active stop"); event("stop"); }
        public void destroy() {
            event("destroy");
            try { write("applet.txt", events); } catch (Exception error) { throw new RuntimeException(error); }
        }
    }
    public static final class FailingApplication {
        public static void main(String[] args) { throw new RuntimeException("authored startup failure"); }
    }
    public static final class FailingApplet extends Applet {
        public void init() { throw new RuntimeException("authored applet init failure"); }
    }
}
