// SPDX-License-Identifier: GPL-3.0-only
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

/** Extracts data only. Never executes an archived program or restores symlinks. */
public final class GameArchive {
    static void extract(Path archive, Path destination) throws IOException {
        long limit = 1024L * 1024 * 1024, total = 0;
        long deadline = System.nanoTime() + 60_000_000_000L;
        if (Files.size(archive) > limit) throw new IOException("Choose a ZIP smaller than 1 GB.");
        Files.createDirectory(destination);
        Path root = destination.toRealPath();
        try (ZipFile zip = new ZipFile(archive.toFile())) {
            if (zip.size() > 10000) throw new IOException("This ZIP contains more than 10,000 entries.");
            Enumeration<? extends ZipEntry> entries = zip.entries();
            byte[] buffer = new byte[32768];
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                String name = entry.getName();
                if (name.isEmpty() || name.startsWith("/") || name.contains("\\") || name.contains(":"))
                    throw new IOException("A ZIP entry has an unsafe path.");
                boolean hidden = false;
                for (String part : name.split("/")) {
                    if (part.isEmpty() || part.equals(".") || part.equals(".."))
                        throw new IOException("A ZIP entry points outside the game folder.");
                    hidden |= part.startsWith(".") || part.equals("__MACOSX");
                }
                Path target = root.resolve(name).normalize();
                if (!target.startsWith(root) || target.equals(root)) throw new IOException("Unsafe ZIP path.");
                if (hidden) continue;
                if (entry.isDirectory()) { Files.createDirectories(target); continue; }
                if (entry.getSize() > limit - total) throw new IOException("The expanded game exceeds 1 GB.");
                Files.createDirectories(target.getParent());
                CRC32 crc = new CRC32();
                long size = 0;
                try (InputStream input = zip.getInputStream(entry);
                     OutputStream output = Files.newOutputStream(target, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        total += count; size += count;
                        if (total > limit) throw new IOException("The expanded game exceeds 1 GB.");
                        if (System.nanoTime() > deadline) throw new IOException("This ZIP took too long to unpack.");
                        output.write(buffer, 0, count); crc.update(buffer, 0, count);
                    }
                }
                if (size != entry.getSize() || crc.getValue() != entry.getCrc())
                    throw new IOException("This ZIP contains a damaged file.");
            }
        }
    }

    public static void main(String[] args) {
        try {
            if (args.length != 2) throw new IOException("Choose a ZIP game archive.");
            extract(Paths.get(args[0]), Paths.get(args[1]));
        } catch (Exception error) {
            System.err.println(error.getMessage() == null ? "This ZIP could not be unpacked." : error.getMessage());
            System.exit(1);
        }
    }
}
