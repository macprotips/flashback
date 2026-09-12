// SPDX-License-Identifier: GPL-3.0-only
import java.io.InputStream;
import javax.microedition.lcdui.*;
import javax.microedition.midlet.MIDlet;
import javax.microedition.rms.RecordStore;

/** Authored MIDlet run through the shipped player, with game permissions. */
public final class J2MEChecks extends MIDlet {
    protected void startApp() {
        try {
            if ("yes".equals(getAppProperty("Flashback-Fail"))) throw new Exception("Intentional startup failure");
            JavaPolicyCheck.main(new String[0]);
            if (!"companion".equals(getAppProperty("Flashback-JAD-Check"))) throw new Exception("JAD was not loaded");
            Canvas canvas = new Canvas() {
                protected void paint(Graphics g) { g.setColor(0x237346); g.fillRect(0, 0, getWidth(), getHeight()); }
            };
            canvas.setFullScreenMode(true);
            Display.getDisplay(this).setCurrent(canvas);
            boolean changed = "yes".equals(getAppProperty("Flashback-Changed-Settings"));
            int width = changed ? 208 : 176, height = changed ? 176 : 208;
            if (canvas.getWidth() != width || canvas.getHeight() != height)
                throw new Exception("Wrong display: " + canvas.getWidth() + "x" + canvas.getHeight());
            if (org.recompile.mobile.Mobile.getMobileKey(9) != (changed ? -1 : -6) ||
                org.recompile.mobile.Mobile.getMobileKey(8) != (changed ? -4 : -7))
                throw new Exception("Wrong phone softkeys");
            if (org.recompile.mobile.Mobile.limitFPS != (changed ? 30 : 60))
                throw new Exception("Wrong frame rate");
            try (InputStream resource = getClass().getResourceAsStream("/check + % # \u00e9.txt")) {
                if (resource == null || resource.read() != 42) throw new Exception("Escaped resource path failed");
            }
            RecordStore store = RecordStore.openRecordStore("FlashbackCheck", true);
            int previous = store.getNumRecords() == 0 ? 0 : store.getRecord(1)[0];
            byte[] saved = {(byte)(previous + 1)};
            if (previous == 0) store.addRecord(saved, 0, 1); else store.setRecord(1, saved, 0, 1);
            store.closeRecordStore();
            System.out.println("FLASHBACK_MIDLET_PASS:" + width + "x" + height + ":saves=" + saved[0]);
        } catch (Exception | AssertionError error) {
            throw new IllegalStateException("MIDlet check failed", error);
        }
    }
    protected void pauseApp() {}
    protected void destroyApp(boolean unconditional) {}
}
