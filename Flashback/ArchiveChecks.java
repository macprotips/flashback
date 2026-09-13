// SPDX-License-Identifier: GPL-3.0-only
import java.io.*;
import java.nio.file.*;
import java.util.zip.*;

public final class ArchiveChecks {
    static void zip(Path file, String... names) throws IOException {
        try (ZipOutputStream zip = new ZipOutputStream(Files.newOutputStream(file))) {
            for (String name : names) {
                zip.putNextEntry(new ZipEntry(name));
                zip.write("game data".getBytes("UTF-8")); zip.closeEntry();
            }
        }
    }
    static void reject(Path archive, Path output) throws IOException {
        try { GameArchive.extract(archive, output); throw new AssertionError("Accepted unsafe ZIP: " + archive); }
        catch (IOException expected) {}
    }
    static void lemmings(Path archive, Path output) throws IOException {
        GameArchive.extract(archive, output);
        if (!Files.exists(output.resolve("VGALEMMI.EXE")) || !Files.exists(output.resolve("MAIN.DAT")))
            throw new AssertionError("Lemmings demo did not unpack its executable and data files");
    }
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("Flashback-zip-check-");
        try {
            Path archive = root.resolve("game.zip"), output = root.resolve("game");
            zip(archive, "Game/index.html", "Game/assets/sprite #1.png", "__MACOSX/._index.html", ".DS_Store");
            GameArchive.extract(archive, output);
            if (!Files.exists(output.resolve("Game/assets/sprite #1.png")) || Files.exists(output.resolve("__MACOSX")))
                throw new AssertionError("Assets or metadata filtering failed");
            int i = 0;
            for (String path : new String[]{"../escaped", "/tmp/escaped", "x/../../escaped", "x\\escaped", "C:/escaped", "x//escaped"}) {
                Path bad = root.resolve("bad" + i + ".zip"); zip(bad, path);
                reject(bad, root.resolve("out" + i++));
            }
            Path collision = root.resolve("collision.zip");
            zip(collision, "assets", "assets/image.png");
            reject(collision, root.resolve("collision"));
            Path large = root.resolve("too-many.zip");
            String[] names = new String[10001]; for (int j=0; j<names.length; j++) names[j]="f"+j;
            zip(large, names); reject(large, root.resolve("large"));
            Path invalid = root.resolve("invalid.zip"); Files.write(invalid, new byte[]{1,2,3});
            reject(invalid, root.resolve("invalid"));
            // Forge an oversized uncompressed size in the central directory without allocating a bomb.
            Path bomb = root.resolve("bomb.zip"); zip(bomb, "huge.dat");
            byte[] data = Files.readAllBytes(bomb);
            for (int j=0; j<data.length-28; j++) if (data[j]==0x50 && data[j+1]==0x4b && data[j+2]==1 && data[j+3]==2) {
                data[j+24]=1; data[j+25]=0; data[j+26]=0; data[j+27]=0x40; break;
            }
            Files.write(bomb, data); reject(bomb, root.resolve("bomb"));
            Path damaged = root.resolve("damaged.zip"); zip(damaged, "game.html");
            data = Files.readAllBytes(damaged);
            for (int j=0; j<data.length-20; j++) if (data[j]==0x50 && data[j+1]==0x4b && data[j+2]==1 && data[j+3]==2) {
                data[j+16] ^= 1; break;
            }
            Files.write(damaged, data); reject(damaged, root.resolve("damaged"));
            if (args.length == 1) lemmings(Paths.get(args[0]), root.resolve("lemmings"));
            else if (args.length != 0) throw new IllegalArgumentException("pass an optional Lemmings demo ZIP");
            System.out.println("PASS: ZIP assets, metadata filtering, traversal, collisions, entry and size limits, invalid archives, damaged checksums, and optional Imploding ZIP");
        } finally {
            try (java.util.stream.Stream<Path> files = Files.walk(root)) {
                files.sorted(java.util.Comparator.reverseOrder()).forEach(path -> { try { Files.delete(path); } catch (IOException ignored) {} });
            }
        }
    }
}
