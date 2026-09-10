// SPDX-License-Identifier: GPL-3.0-only
import java.awt.*;
import java.io.*;
import java.net.*;
import java.security.*;
import java.util.jar.*;
import jdk.internal.org.objectweb.asm.*;
import jdk.internal.org.objectweb.asm.tree.*;

/** Repairs the original Wiz 3 v4 display path while leaving its JAR untouched. */
final class Wiz3Display extends URLClassLoader {
    private static final String CLASS = "com/eaborn/wiz3/Wiz3";
    private static final String SHA256 = "0dc41077fb7c00a99ab2d698ed5b60c1557c834b90b1d5ee6e9fac4a44d0807a";
    private final File file;

    Wiz3Display(File file) throws MalformedURLException {
        super(new URL[] {file.toURI().toURL()}, JavaRunner.class.getClassLoader());
        this.file = file;
    }

    @Override protected Class<?> findClass(String name) throws ClassNotFoundException {
        if (!name.equals(CLASS.replace('/', '.'))) return super.findClass(name);
        try (JarFile jar = new JarFile(file, true)) {
            JarEntry entry = jar.getJarEntry(CLASS + ".class");
            if (entry == null || entry.getSize() != 11455) return super.findClass(name);
            byte[] bytes;
            try (InputStream input = jar.getInputStream(entry); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] chunk = new byte[4096]; int count;
                while ((count = input.read(chunk)) != -1) {
                    output.write(chunk, 0, count);
                    if (output.size() > 11455) throw new IOException("Unexpected Wiz 3 class size.");
                }
                bytes = output.toByteArray();
            }
            StringBuilder digest = new StringBuilder();
            for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) digest.append(String.format("%02x", value & 255));
            if (!digest.toString().equals(SHA256)) return super.findClass(name);
            bytes = repair(bytes);
            // Preserve the game's source and signer identity: repaired game code still has game permissions.
            CodeSource source = new CodeSource(file.toURI().toURL(), entry.getCodeSigners());
            System.out.println("FLASHBACK_WIZ3_DISPLAY_FIX");
            return defineClass(name, bytes, 0, bytes.length, source);
        } catch (Exception error) { throw new ClassNotFoundException("Wiz 3 display compatibility could not load.", error); }
    }

    private static byte[] repair(byte[] original) throws IOException {
        ClassNode node = new ClassNode();
        new ClassReader(original).accept(node, 0);
        int replaced = 0;
        for (MethodNode method : node.methods) {
            for (AbstractInsnNode instruction = method.instructions.getFirst(); instruction != null; ) {
                AbstractInsnNode next = instruction.getNext();
                if (instruction instanceof FieldInsnNode) {
                    FieldInsnNode field = (FieldInsnNode)instruction;
                    if (field.getOpcode() == Opcodes.GETSTATIC && field.owner.equals(CLASS) && field.name.equals("gMain")) {
                        AbstractInsnNode end = instruction;
                        while (end != null && !(end instanceof MethodInsnNode && ((MethodInsnNode)end).owner.equals("java/awt/Graphics") && ((MethodInsnNode)end).name.equals("drawImage"))) end = end.getNext();
                        if (end == null || end.getNext().getOpcode() != Opcodes.POP) throw new IOException("Unexpected Wiz 3 drawing instructions.");
                        AbstractInsnNode after = end.getNext().getNext();
                        InsnList repaint = new InsnList();
                        repaint.add(new VarInsnNode(Opcodes.ALOAD, 0));
                        repaint.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/awt/Component", "repaint", "()V", false));
                        method.instructions.insertBefore(instruction, repaint);
                        while (instruction != after) {
                            AbstractInsnNode following = instruction.getNext();
                            method.instructions.remove(instruction); instruction = following;
                        }
                        next = after; replaced++;
                    }
                }
                instruction = next;
            }
            if (method.name.equals("paint") && method.desc.equals("(Ljava/awt/Graphics;)V")) {
                method.instructions.clear();
                method.instructions.add(new VarInsnNode(Opcodes.ALOAD, 0));
                method.instructions.add(new VarInsnNode(Opcodes.ALOAD, 1));
                method.instructions.add(new FieldInsnNode(Opcodes.GETSTATIC, CLASS, "buffer", "Ljava/awt/Image;"));
                method.instructions.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "JavaRunner", "paintWiz3", "(Ljava/awt/Component;Ljava/awt/Graphics;Ljava/awt/Image;)V", false));
                method.instructions.add(new InsnNode(Opcodes.RETURN));
                if (method.localVariables != null) method.localVariables.clear();
            }
        }
        if (replaced != 5) throw new IOException("Wiz 3 drawing instructions did not match this compatibility fix.");
        MethodNode update = new MethodNode(Opcodes.ACC_PUBLIC, "update", "(Ljava/awt/Graphics;)V", null, null);
        update.instructions.add(new VarInsnNode(Opcodes.ALOAD, 0));
        update.instructions.add(new VarInsnNode(Opcodes.ALOAD, 1));
        update.instructions.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, CLASS, "paint", "(Ljava/awt/Graphics;)V", false));
        update.instructions.add(new InsnNode(Opcodes.RETURN));
        node.methods.add(update);
        // Existing stack-map boundaries are unchanged; each replaced blit and repaint leaves an empty stack.
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        node.accept(writer);
        return writer.toByteArray();
    }
}
