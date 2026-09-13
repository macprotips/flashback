// SPDX-License-Identifier: GPL-3.0-only
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry;
import org.apache.commons.compress.archivers.zip.ZipFile;

/** Extracts data only. Never executes an archived program or restores symlinks. */
public final class GameArchive {
    static void extract(Path archive, Path destination) throws IOException {
        long limit = 1024L * 1024 * 1024, total = 0;
        long deadline = System.nanoTime() + 60_000_000_000L;
        if (Files.size(archive) > limit) throw new IOException("Choose a ZIP smaller than 1 GB.");
        Files.createDirectory(destination);
        Path root = destination.toRealPath();
        try (ZipFile zip = ZipFile.builder().setFile(archive.toFile()).get()) {
            Enumeration<ZipArchiveEntry> entries = zip.getEntries();
            byte[] buffer = new byte[32768];
            int entriesSeen = 0;
            while (entries.hasMoreElements()) {
                if (++entriesSeen > 10000) throw new IOException("This ZIP contains more than 10,000 entries.");
                if (System.nanoTime() > deadline) throw new IOException("This ZIP took too long to unpack.");
                ZipArchiveEntry entry = entries.nextElement();
                String name = entry.getName();
                byte[] rawName = entry.getRawName();
                boolean unsafeSeparator = false;
                for (byte character : rawName) unsafeSeparator |= character == '\\' || character == ':';
                if (name.isEmpty() || name.startsWith("/") || unsafeSeparator)
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
                if (entry.isUnixSymlink()) throw new IOException("A ZIP entry is a symbolic link.");
                long expectedSize = entry.getSize(), expectedCrc = entry.getCrc();
                if (expectedSize < 0 || expectedCrc < 0 || expectedSize > limit - total)
                    throw new IOException("This ZIP contains an invalid or oversized file.");
                if (!zip.canReadEntryData(entry)) throw new IOException("This ZIP uses an unsupported encrypted or compressed file.");
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
                if (size != expectedSize || crc.getValue() != expectedCrc)
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
