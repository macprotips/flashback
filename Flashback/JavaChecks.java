// SPDX-License-Identifier: GPL-3.0-only
import java.applet.Applet;
import java.awt.*;
import java.awt.event.*;
import java.awt.image.BufferedImage;
import java.io.*;
import java.nio.file.*;
import javax.imageio.ImageIO;

/** Checks the production loader and actual AWT paint/window path, not the game's private buffer. */
public final class JavaChecks {
    static Applet game;
    static Frame frame;
    static File output;
    static void colorful(BufferedImage image, String stage) {
        int colored = 0;
        for (int y = 0; y < image.getHeight(); y += 4) for (int x = 0; x < image.getWidth(); x += 4) {
            int rgb = image.getRGB(x, y), r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
            if (Math.max(r, Math.max(g, b)) - Math.min(r, Math.min(g, b)) > 35) colored++;
        }
        if (colored < image.getWidth() * image.getHeight() / 1600)
            throw new AssertionError(stage + ": the window is blank or missing the game image");
    }
    static void render(String stage) throws Exception {
        EventQueue.invokeAndWait(() -> { frame.toFront(); game.requestFocus(); });
        Thread.sleep(800);
        BufferedImage painted = new BufferedImage(game.getWidth(), game.getHeight(), BufferedImage.TYPE_INT_RGB);
        EventQueue.invokeAndWait(() -> {
            Graphics2D canvas = painted.createGraphics();
            game.paintAll(canvas); canvas.dispose();
        });
        ImageIO.write(painted, "png", new File(output, stage + "-paint.png"));
        colorful(painted, stage + " AWT paint");
        // Capture only this test game's client rectangle after bringing its own window forward.
        Point origin = game.getLocationOnScreen();
        BufferedImage visible = new Robot(game.getGraphicsConfiguration().getDevice())
            .createScreenCapture(new Rectangle(origin, game.getSize()));
        ImageIO.write(visible, "png", new File(output, stage + "-window.png"));
        colorful(visible, stage + " on-screen window");
    }
    static void key(int code, char character, boolean pressed) throws Exception {
        EventQueue.invokeAndWait(() -> {
            KeyEvent event = new KeyEvent(game, pressed ? KeyEvent.KEY_PRESSED : KeyEvent.KEY_RELEASED,
                System.currentTimeMillis(), 0, code, character);
            for (KeyListener listener : game.getKeyListeners()) {
                if (pressed) listener.keyPressed(event); else listener.keyReleased(event);
            }
        });
    }
    public static void main(String[] args) {
        try {
            output = new File(args[1]);
            Thread.setDefaultUncaughtExceptionHandler((thread, error) -> { error.printStackTrace(); System.exit(1); });
            JavaRunner.launch(new File(args[0]));
            Thread.sleep(2000);
            for (Frame candidate : Frame.getFrames()) if (candidate.isShowing()) frame = candidate;
            if (frame == null) throw new AssertionError("No visible game window");
            for (Component child : frame.getComponents()) if (child instanceof Applet) game = (Applet)child;
            if (game == null) throw new AssertionError("No game component");
            if (game.getClass().getProtectionDomain().implies(new FilePermission("/usr/bin/true", "execute")))
                throw new AssertionError("Game code acquired host permissions");
            EventQueue.invokeAndWait(() -> { frame.setAlwaysOnTop(true); frame.setLocation(80, 80); frame.toFront(); game.requestFocus(); });
            render("Title");
            key(KeyEvent.VK_S, 's', true); key(KeyEvent.VK_S, 's', false);
            Thread.sleep(700);
            render("Playing");
            key(KeyEvent.VK_RIGHT, KeyEvent.CHAR_UNDEFINED, true);
            Thread.sleep(200);
            key(KeyEvent.VK_RIGHT, KeyEvent.CHAR_UNDEFINED, false);
            render("Movement");
            Dimension size = frame.getSize();
            EventQueue.invokeAndWait(() -> { frame.setResizable(true); frame.setSize(size.width + 100, size.height + 60); });
            render("Resized");
            EventQueue.invokeAndWait(() -> frame.setState(Frame.ICONIFIED));
            Thread.sleep(600);
            EventQueue.invokeAndWait(() -> { frame.setState(Frame.NORMAL); frame.toFront(); game.requestFocus(); });
            Thread.sleep(800);
            render("Restored");
            String result = "PASS: production Wiz 3 loader, restricted game permissions, nonblank AWT paint and actual window, start/movement input, resize, and minimize/restore";
            Files.write(new File(output, "Result.txt").toPath(), (result + "\n").getBytes("UTF-8"));
            System.out.println(result);
            EventQueue.invokeAndWait(() -> frame.dispatchEvent(new WindowEvent(frame, WindowEvent.WINDOW_CLOSING)));
            System.exit(0);
        } catch (Throwable error) { error.printStackTrace(); System.exit(1); }
    }
}
