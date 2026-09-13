// SPDX-License-Identifier: GPL-3.0-only
import java.applet.*;
import java.awt.*;
import java.awt.event.*;
import java.io.*;
import java.lang.reflect.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.jar.*;
import javax.xml.XMLConstants;
import javax.xml.parsers.*;
import org.w3c.dom.*;

/** A small, separately sandboxed host for classic Java games and applets. */
public final class JavaRunner {
    static Class<?> gameClass;
    private static Applet runningApplet;
    private static Frame appletWindow;
    private static volatile boolean appletStarted;

    private static final class Launch {
        final File source, base; final String kind, main; final URL[] jars;
        final String[] arguments; final Map<String, String> parameters; final int width, height;
        Launch(File source, File base, String kind, String main, URL[] jars, String[] arguments,
               Map<String, String> parameters, int width, int height) {
            this.source=source; this.base=base; this.kind=kind; this.main=main; this.jars=jars;
            this.arguments=arguments; this.parameters=parameters; this.width=width; this.height=height;
        }
    }
    static Manifest manifest(File file) throws IOException {
        try (JarFile jar = new JarFile(file)) {
            JarEntry entry = jar.getJarEntry("META-INF/MANIFEST.MF");
            if (entry == null || entry.getSize() < 0 || entry.getSize() > 65536)
                throw new IOException("This JAR needs a valid application manifest (at most 64 KB).");
            try (InputStream stream = jar.getInputStream(entry)) { return new Manifest(stream); }
        }
    }

    static Properties descriptor(File jar) throws IOException {
        Properties values = new Properties();
        Attributes attributes = manifest(jar).getMainAttributes();
        for (Object key : attributes.keySet()) {
            Attributes.Name name = (Attributes.Name)key;
            values.setProperty(name.toString(), attributes.getValue(name));
        }
        String name = jar.getName();
        File jad = new File(jar.getParentFile(), name.substring(0, name.length() - 4) + ".jad");
        if (jad.isFile() && jad.length() <= 65536) {
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(jad), StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    int colon = line.indexOf(':');
                    if (colon > 0) values.setProperty(line.substring(0, colon).trim(), line.substring(colon + 1).trim());
                }
            }
        }
        return values;
    }

    static int number(Properties values, String... names) {
        for (String name : names) {
            String value = values.getProperty(name);
            if (value == null) continue;
            try { return Integer.parseInt(value.trim()); } catch (NumberFormatException ignored) { }
        }
        return 0;
    }

    static int[] displaySize(Properties values) throws IOException {
        String[] names = {"Nokia-MIDlet-Original-Display-Size", "Nokia-MIDlet-Target-Display-Size",
                          "MIDlet-Display-Size", "MIDlet-Display-Resolution", "Display-Size"};
        for (String name : names) {
            String value = values.getProperty(name);
            if (value == null) continue;
            java.util.regex.Matcher matcher = java.util.regex.Pattern.compile("(\\d+)\\s*[xX,]\\s*(\\d+)").matcher(value.trim());
            if (matcher.matches()) {
                try { return new int[] {Integer.parseInt(matcher.group(1)), Integer.parseInt(matcher.group(2))}; }
                catch (NumberFormatException invalid) { throw new IOException("Invalid Java ME display size: " + value); }
            }
            throw new IOException("Invalid Java ME display size: " + value);
        }
        int width = number(values, "MIDlet-Display-Width", "Nokia-MIDlet-Display-Width", "Screen-Width");
        int height = number(values, "MIDlet-Display-Height", "Nokia-MIDlet-Display-Height", "Screen-Height");
        return width > 0 && height > 0 ? new int[] {width, height} : new int[] {240, 320};
    }

    static String[] j2meArguments(File file) throws IOException {
        Properties values = descriptor(file);
        int[] size = displaySize(values);
        if (size[0] < 1 || size[0] > 2000 || size[1] < 1 || size[1] > 2000)
            throw new IOException("The Java ME display dimensions must be between 1 and 2000 pixels.");
        int scale = Math.max(size[0], size[1]) <= 320 ? 2 : 1;
        int keyLayout = 0;
        String platform = (values.getProperty("Nokia-Platform", "") + " " +
                           values.getProperty("MIDlet-Vendor", "")).toLowerCase(Locale.ROOT);
        // Standard already uses Nokia's numeric keypad; NokiaKeyboard is QWERTY.
        if (platform.contains("motorola")) keyLayout = 2;
        else if (platform.contains("siemens")) keyLayout = 7;
        int fps = number(values, "MIDlet-FPS", "Nokia-MIDlet-FPS");
        if (fps <= 0) fps = 60;
        if (fps > 120) throw new IOException("The Java ME frame rate must be at most 120 FPS.");
        return new String[] {file.toURI().toASCIIString(), "0", "" + size[0], "" + size[1],
                             "" + scale, "" + keyLayout, "" + fps, "0"};
    }

    static String j2meConfig(File file) throws IOException {
        String[] args = j2meArguments(file);
        return "J2ME_CONFIG\t" + String.join("\t", java.util.Arrays.copyOfRange(args, 2, 7));
    }

    private static boolean className(String value) {
        return value != null && value.matches("[A-Za-z_$][A-Za-z0-9_$]*(\\.[A-Za-z_$][A-Za-z0-9_$]*)*");
    }
    private static void ensureContained(File root, File candidate, String what) throws IOException {
        if (!candidate.getCanonicalPath().startsWith(root.getCanonicalPath()+File.separator) && !candidate.getCanonicalFile().equals(root.getCanonicalFile())) throw new IOException("The "+what+" escapes this game's folder.");
    }
    private static File localResource(File base, File root, String href, String what) throws IOException {
        if (href == null || href.trim().isEmpty()) throw new IOException("The JNLP "+what+" needs a local href.");
        try {
            URI uri=new URI(href.trim());
            if(uri.isAbsolute() || uri.getAuthority()!=null || uri.getRawQuery()!=null || uri.getRawFragment()!=null) throw new IOException("The JNLP "+what+" must be a local relative path; network URLs are not supported.");
            File result=new File(base, uri.getPath()).getCanonicalFile();
            ensureContained(root,result,what);
            return result;
        }
        catch (URISyntaxException bad) {
            throw new IOException("The JNLP "+what+" path is invalid: "+href);
        }
    }
    private static String attribute(Element element, String name, String message) throws IOException {
        String value=element.getAttribute(name).trim();
        if(value.isEmpty())throw new IOException(message);
        return value;
    }
    private static int dimension(Element element, String name, int fallback) throws IOException {
        String value=element.getAttribute(name).trim();
        if(value.isEmpty())return fallback;
        try {
            int result=Integer.parseInt(value);
            if(result<1||result>4096)throw new NumberFormatException();
            return result;
        } catch(NumberFormatException error) {
            throw new IOException("The applet "+name+" must be between 1 and 4096 pixels.");
        }
    }
    private static Document xml(File file) throws IOException {
        try {
            DocumentBuilderFactory f=DocumentBuilderFactory.newInstance();
            f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING,true);
            f.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);
            f.setFeature("http://xml.org/sax/features/external-general-entities",false);
            f.setFeature("http://xml.org/sax/features/external-parameter-entities",false);
            f.setXIncludeAware(false);
            f.setExpandEntityReferences(false);
            try(InputStream input=new FileInputStream(file)) {
                return f.newDocumentBuilder().parse(input);
            }
        }
        catch(Exception error) {
            throw new IOException("This JNLP descriptor is not safe, local XML: "+error.getMessage(),error);
        }
    }
    private static Launch jnlp(File descriptor) throws IOException {
        File source=descriptor.getCanonicalFile(), descriptorBase=source.getParentFile();
        String configuredRoot=System.getProperty("flashback.game","");
        File gameRoot=configuredRoot.isEmpty()?descriptorBase:new File(configuredRoot).getCanonicalFile();
        ensureContained(gameRoot,source,"JNLP descriptor");
        if(source.length()>2*1024*1024)throw new IOException("The JNLP descriptor is too large.");
        Document doc=xml(source);
        Element root=doc.getDocumentElement();
        if(!"jnlp".equals(root.getTagName()))throw new IOException("This file is not a JNLP descriptor.");
        String codebase=root.getAttribute("codebase").trim();
        File base=codebase.isEmpty()?descriptorBase:localResource(descriptorBase,gameRoot,codebase,"codebase");
        NodeList security=root.getElementsByTagName("security");
        for(int i=0;i<security.getLength();i++)for(Node child=security.item(i).getFirstChild();child!=null;child=child.getNextSibling())if(child instanceof Element && !"sandbox".equals(((Element)child).getTagName())) {
            if("all-permissions".equals(((Element)child).getTagName()))throw new IOException("This JNLP requests all-permissions, which Flashback does not grant.");
            throw new IOException("This JNLP requests an unsupported security extension.");
        }
        if(root.getElementsByTagName("extension").getLength()>0)throw new IOException("JNLP extension descriptors are not supported; include the game's local JARs directly.");
        if(root.getElementsByTagName("nativelib").getLength()>0)throw new IOException("JNLP native libraries are not supported.");
        if(root.getElementsByTagName("installer-desc").getLength()>0)throw new IOException("JNLP installer descriptors are not games Flashback can run.");
        if(root.getElementsByTagName("property").getLength()>0)throw new IOException("JNLP system properties are not supported.");
        ArrayList<URL> jars=new ArrayList<URL>();
        NodeList resources=root.getElementsByTagName("resources");
        for(int i=0;i<resources.getLength();i++) {
            Element resource=(Element)resources.item(i);
            if(resource.hasAttribute("os") || resource.hasAttribute("arch") || resource.hasAttribute("locale"))throw new IOException("Platform-specific JNLP resources are not supported.");
            Node child=resource.getFirstChild();
            while(child!=null) {
                if(child instanceof Element && "jar".equals(((Element)child).getTagName())) {
                    File jar=localResource(base,gameRoot,((Element)child).getAttribute("href"),"JAR");
                    if(!jar.isFile())throw new IOException("The JNLP JAR is missing: "+jar.getName());
                    jars.add(jar.toURI().toURL());
                }child=child.getNextSibling();
            }
        }
        NodeList applications=root.getElementsByTagName("application-desc"), applets=root.getElementsByTagName("applet-desc");
        if(applications.getLength()+applets.getLength()!=1)throw new IOException("A JNLP descriptor must have exactly one application-desc or applet-desc.");
        Element app=(Element)(applications.getLength()==1?applications.item(0):applets.item(0));
        String kind=applications.getLength()==1?"JNLP:APPLICATION":"JNLP:APPLET";
        if(kind.equals("JNLP:APPLET")) jars.add(base.toURI().toURL());
        if(jars.isEmpty())throw new IOException("This JNLP descriptor needs at least one local JAR resource.");
        if(jars.size()>129)throw new IOException("This JNLP descriptor lists too many JARs.");
        String main=attribute(app,"main-class","The JNLP launch descriptor needs a main-class.");
        if(!className(main))throw new IOException("The JNLP main-class is invalid.");
        ArrayList<String> arguments=new ArrayList<String>();
        Map<String,String> parameters=new LinkedHashMap<String,String>();
        for(Node child=app.getFirstChild();child!=null;child=child.getNextSibling())if(child instanceof Element) {
            Element value=(Element)child;
            if("argument".equals(value.getTagName()))arguments.add(value.getTextContent());
            else if("param".equals(value.getTagName()))parameters.put(attribute(value,"name","An applet parameter needs a name."),value.getAttribute("value"));
        }
        return new Launch(source,base,kind,main,jars.toArray(new URL[jars.size()]),arguments.toArray(new String[arguments.size()]),parameters,dimension(app,"width",640),dimension(app,"height",480));
    }
    /* Reads only class-file metadata, so --inspect never executes game code. */
    private static String superClass(JarFile jar, String internal) throws IOException {
        JarEntry e=jar.getJarEntry(internal+".class");
        if(e==null)return null;
        try(DataInputStream in=new DataInputStream(jar.getInputStream(e))) {
            if(in.readInt()!=0xcafebabe)throw new IOException("Invalid class file in JAR.");
            in.readUnsignedShort();
            in.readUnsignedShort();
            Object[] pool=new Object[in.readUnsignedShort()];
            for(int i=1;i<pool.length;i++) {
                int tag=in.readUnsignedByte();
                switch(tag) {
                    case 1:pool[i]=in.readUTF();
                    break;
                    case 7:case 8:case 16:pool[i]=Integer.valueOf(in.readUnsignedShort());
                    break;
                    case 3:case 4:in.readInt();
                    break;
                    case 5:case 6:in.readLong();
                    i++;
                    break;
                    case 9:case 10:case 11:case 12:case 18:in.readUnsignedShort();
                    in.readUnsignedShort();
                    break;
                    case 15:in.readUnsignedByte();
                    in.readUnsignedShort();
                    break;
                    default:throw new IOException("Unsupported class metadata.");
                }
            }in.readUnsignedShort();
            in.readUnsignedShort();
            int parent=in.readUnsignedShort();
            return parent==0?null:(String)pool[((Integer)pool[parent]).intValue()];
        }
    }
    private static boolean appletClass(JarFile jar,String name) throws IOException {
        for(int depth=0;name!=null&&depth<64;depth++) {
            if(name.equals("java/applet/Applet")||name.equals("javax/swing/JApplet"))return true;
            name=superClass(jar,name);
        }return false;
    }
    private static Launch jar(File file) throws IOException {
        File source=file.getCanonicalFile();
        try(JarFile contents=new JarFile(source)) {
            Attributes a=contents.getJarEntry("META-INF/MANIFEST.MF")==null?new Attributes():manifest(source).getMainAttributes();
            String midlet=a.getValue("MIDlet-1");
            if(midlet!=null) {
                String[] fields=midlet.split(",",-1);
                String entry=fields.length==3?fields[2].trim():"";
                if(!className(entry)||contents.getJarEntry(entry.replace('.','/')+".class")==null)throw new IOException("The game's MIDlet class is missing from this JAR.");
                return new Launch(source,source.getParentFile(),"J2ME",entry,new URL[0],new String[0],Collections.<String,String>emptyMap(),0,0);
            }String main=a.getValue(Attributes.Name.MAIN_CLASS);
            if(main!=null) {
                if(!className(main)||contents.getJarEntry(main.replace('.','/')+".class")==null)throw new IOException("The game's main class is missing from this JAR.");
                return new Launch(source,source.getParentFile(),"DESKTOP",main,new URL[] {
                    source.toURI().toURL()
                },new String[0],Collections.<String,String>emptyMap(),0,0);
            }String declared=a.getValue("Applet-Class");
            if(declared==null)declared=a.getValue("Java-Applet-Class");
            if(declared!=null) {
                if(!className(declared)||!appletClass(contents,declared.replace('.','/')))throw new IOException("The JAR's Applet-Class is not a java.applet.Applet.");
                return new Launch(source,source.getParentFile(),"APPLET",declared,new URL[] {
                    source.toURI().toURL()
                },new String[0],Collections.<String,String>emptyMap(),640,480);
            }ArrayList<String> found=new ArrayList<String>();
            Enumeration<JarEntry> es=contents.entries();
            while(es.hasMoreElements()) {
                JarEntry e=es.nextElement();
                if(e.getName().endsWith(".class")&&appletClass(contents,e.getName().substring(0,e.getName().length()-6)))found.add(e.getName().substring(0,e.getName().length()-6).replace('/','.'));
            }if(found.size()==1)return new Launch(source,source.getParentFile(),"APPLET",found.get(0),new URL[] {
                source.toURI().toURL()
            },new String[0],Collections.<String,String>emptyMap(),640,480);
            if(found.size()>1)throw new IOException("This applet JAR has multiple applet classes. Import a local JNLP descriptor to select one.");
            throw new IOException("This is not a standalone Java game. Use a runnable JAR, an applet JAR, a local JNLP descriptor, or a Java ME JAR.");
        }
    }
    private static Launch inspectLaunch(File file) throws IOException {
        if(!file.isFile())throw new IOException("The Java game file is missing.");
        return file.getName().toLowerCase(Locale.ROOT).endsWith(".jnlp")?jnlp(file):jar(file);
    }
    /** Classifies a game without loading or initializing any game classes. */
    public static String inspect(File file) throws IOException {
        Launch l=inspectLaunch(file);
        return l.kind.equals("DESKTOP")?"DESKTOP:"+l.main:l.kind.equals("APPLET")?"APPLET:"+l.main:l.kind;
    }
    public static String mainClass(File file) throws IOException {
        Launch l=inspectLaunch(file);
        if(!l.kind.equals("DESKTOP"))throw new IOException("This is not a standalone desktop Java application.");
        return l.main;
    }
    private static void validateClassPath(Launch launch) throws Exception {
        File root = new File(System.getProperty("flashback.game", launch.source.getParent())).getCanonicalFile();
        ArrayDeque<File> pending = new ArrayDeque<File>();
        HashSet<File> seen = new HashSet<File>();
        for (URL url : launch.jars) pending.add(new File(url.toURI()));
        while (!pending.isEmpty()) {
            File file = pending.removeFirst().getCanonicalFile();
            ensureContained(root, file, "Java classpath");
            if (!seen.add(file) || file.isDirectory()) continue;
            if (seen.size() > 128) throw new IOException("The Java classpath contains too many archives.");
            try (JarFile jar = new JarFile(file)) {
                if (jar.getJarEntry("META-INF/MANIFEST.MF") == null) continue;
                String paths = manifest(file).getMainAttributes().getValue(Attributes.Name.CLASS_PATH);
                if (paths != null) for (String path : paths.trim().split("\\s+")) {
                    if (!path.isEmpty()) pending.add(localResource(file.getParentFile(), root, path, "manifest Class-Path"));
                }
            }
        }
    }
    private static URLClassLoader loader(Launch l) throws Exception {
        validateClassPath(l);
        if(l.kind.equals("DESKTOP")&&l.jars.length==1)return new Wiz3Display(l.source);
        return new URLClassLoader(l.jars,JavaRunner.class.getClassLoader());
    }
    private static final class Stub implements AppletStub, AppletContext {
        final Launch launch;
        final Applet applet;
        volatile boolean active=false;
        Stub(Launch launch,Applet applet) {
            this.launch=launch;
            this.applet=applet;
        }
        public boolean isActive() {
            return active;
        } public URL getDocumentBase() {
            try {
                return launch.source.toURI().toURL();
            }catch(MalformedURLException e) {
                throw new AssertionError(e);
            }
        } public URL getCodeBase() {
            try {
                return launch.base.toURI().toURL();
            }catch(MalformedURLException e) {
                throw new AssertionError(e);
            }
        } public String getParameter(String name) {
            return launch.parameters.get(name);
        } public AppletContext getAppletContext() {
            return this;
        }
        public void appletResize(int width,int height) {
            if(appletWindow!=null)appletWindow.setSize(Math.max(1,width),Math.max(1,height));
        }
        public AudioClip getAudioClip(URL url) {
            return Applet.newAudioClip(url);
        } public Image getImage(URL url) {
            return Toolkit.getDefaultToolkit().createImage(url);
        } public Applet getApplet(String name) {
            return applet.getName()!=null&&applet.getName().equals(name)?applet:null;
        } public Enumeration<Applet> getApplets() {
            return Collections.enumeration(Collections.singletonList(applet));
        } public void showDocument(URL url) {
            throw new SecurityException("Opening web pages is not supported by the offline Java player.");
        } public void showDocument(URL url,String target) {
            showDocument(url);
        } public void showStatus(String status) {
            System.out.println("FLASHBACK_STATUS "+status);
        } public void setStream(String key,InputStream stream) throws IOException {
            throw new IOException("Applet streams are not supported.");
        } public InputStream getStream(String key) {
            return null;
        } public Iterator<String> getStreamKeys() {
            return Collections.<String>emptyList().iterator();
        }
    }
    static Applet startAppletForCheck(File file) throws Exception {
        Launch l=inspectLaunch(file);
        return startApplet(l);
    }
    static void stopAppletForCheck(Applet applet) {
        ((Stub)applet.getAppletContext()).active=false;
        try {
            applet.stop();
        } finally {
            applet.destroy();
        }
    }
    private static Applet startApplet(Launch l) throws Exception {
        if(!(l.kind.equals("APPLET")||l.kind.equals("JNLP:APPLET")))throw new IOException("Not an applet.");
        URLClassLoader loader=loader(l);
        Thread.currentThread().setContextClassLoader(loader);
        Class<?> type=Class.forName(l.main,false,loader);
        if(type.getClassLoader()!=loader)throw new IOException("The entry class must come from the game, not the trusted Java host.");
        if(!Applet.class.isAssignableFrom(type))throw new IOException("The selected applet class does not extend java.applet.Applet.");
        Applet applet=(Applet)type.newInstance();
        Stub stub=new Stub(l,applet);
        applet.setStub(stub);
        applet.setName(l.main);
        applet.setSize(l.width,l.height);
        applet.setPreferredSize(new Dimension(l.width,l.height));
        applet.init();
        stub.active=true;
        applet.start();
        appletStarted=true;
        return applet;
    }
    private static void launchApplet(final Launch l) throws Exception {
        Applet applet=startApplet(l);
        runningApplet=applet;
        EventQueue.invokeAndWait(new Runnable() {
            public void run() {
                Frame frame=new Frame(System.getProperty("flashback.title","Flashback Java Game"));appletWindow=frame;frame.setLayout(new BorderLayout());frame.add(runningApplet,BorderLayout.CENTER);frame.pack();frame.addWindowListener(new WindowAdapter() {
                    public void windowClosing(WindowEvent event) {
                        shutdown();
                    }
                });frame.setVisible(true);
            }
        });
    }
    static void shutdown() {
        Applet applet;
        Frame frame;
        synchronized (JavaRunner.class) {
            applet = runningApplet;
            runningApplet = null;
            frame = appletWindow;
            appletWindow = null;
        }
        try {
            if (applet != null) stopAppletForCheck(applet);
        }
        catch (Throwable error) {
            error.printStackTrace();
        }
        finally {
            if (frame != null) frame.dispose();
        }
    }
    static void launch(File file) throws Exception {
        Launch l=inspectLaunch(file);
        if(l.kind.equals("J2ME")) {
            Class.forName("org.recompile.freej2me.FreeJ2ME").getMethod("main",String[].class).invoke(null,(Object)j2meArguments(file));
            return;
        }if(l.kind.equals("APPLET")||l.kind.equals("JNLP:APPLET")) {
            launchApplet(l);
            return;
        }URLClassLoader loader=loader(l);
        Thread.currentThread().setContextClassLoader(loader);
        gameClass=Class.forName(l.main,false,loader);
        if(gameClass.getClassLoader()!=loader)throw new IOException("The entry class must come from the game, not the trusted Java host.");
        Method main=gameClass.getMethod("main",String[].class);
        if(!Modifier.isStatic(main.getModifiers())||main.getReturnType()!=Void.TYPE)throw new IOException("This JAR does not have a runnable main method.");
        main.invoke(null,(Object)l.arguments);
    }
    public static void paintWiz3(Component component, Graphics graphics, Image image) {
        if(image==null)return;
        Graphics2D canvas=(Graphics2D)graphics.create();
        try {
            canvas.setRenderingHint(RenderingHints.KEY_INTERPOLATION,RenderingHints.VALUE_INTERPOLATION_NEAREST_NEIGHBOR);
            double scale=Math.min(component.getWidth()/480.0,component.getHeight()/248.0);
            int width=(int)Math.round(480*scale),height=(int)Math.round(248*scale),x=(component.getWidth()-width)/2,y=(component.getHeight()-height)/2;
            canvas.setColor(Color.BLACK);
            canvas.fillRect(0,0,component.getWidth(),component.getHeight());
            canvas.drawImage(image,x,y,x+width,y+height,16,0,496,248,component);
        }finally {
            canvas.dispose();
        }
    }
    public static void main(String[] args) {
        try {
            if(args.length!=2)throw new IOException("Choose a Java game from Flashback.");
            File file=new File(args[1]).getCanonicalFile();
            if(args[0].equals("--inspect")) {
                System.out.println(inspect(file));
                return;
            }if(args[0].equals("--j2me-config")) {
                System.out.println(j2meConfig(file));
                return;
            }if(!args[0].equals("--play"))throw new IOException("Unknown player command.");
            final String kind=inspect(file);
            final boolean phone=kind.equals("J2ME"),applet=kind.startsWith("APPLET:")||kind.equals("JNLP:APPLET");
            Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
                public void uncaughtException(Thread t,Throwable e) {
                    e.printStackTrace();System.exit(1);
                }
            });
            Thread parent=new Thread(new Runnable() {
                public void run() {
                    try {
                        while(System.in.read()!=-1) {
                        }
                    }catch(IOException ignored) {
                    }shutdown();System.exit(0);
                }
            },"Flashback parent connection");
            parent.setDaemon(true);
            parent.start();
            Runtime.getRuntime().addShutdownHook(new Thread(JavaRunner::shutdown,"Flashback applet shutdown"));
            Thread monitor=new Thread(new Runnable() {
                public void run() {
                    boolean opened=false;try {
                        for(int second=0;;second++) {
                            final boolean[] visible= {
                                false
                            };EventQueue.invokeAndWait(new Runnable() {
                                public void run() {
                                    for(Window window:Window.getWindows())visible[0]|=window.isShowing();
                                }
                            });if(visible[0]&&!opened&&(!phone||Boolean.getBoolean("flashback.j2me.started"))&&(!applet||appletStarted)) {
                                opened=true;System.out.println("FLASHBACK_READY");System.out.flush();
                            }else if(!visible[0]&&opened) {
                                shutdown();System.exit(0);
                            }if(!opened&&second>=30)throw new IOException("The game did not open a window.");Thread.sleep(1000);
                        }
                    }catch(Throwable error) {
                        error.printStackTrace();shutdown();System.exit(1);
                    }
                }
            },"Flashback game monitor");
            monitor.start();
            launch(file);
        }catch(Throwable error) {
            Throwable cause=error instanceof InvocationTargetException?error.getCause():error;
            cause.printStackTrace();
            shutdown();
            System.exit(1);
        }
    }
}
