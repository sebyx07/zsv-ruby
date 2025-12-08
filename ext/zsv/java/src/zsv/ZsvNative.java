// JNI wrapper for zsv C library
// This provides native bindings to the zsv SIMD-accelerated CSV parser

package zsv;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

/**
 * Native JNI wrapper for the zsv C library.
 * Provides SIMD-accelerated CSV parsing for JRuby.
 */
public class ZsvNative {
    private static boolean loaded = false;
    private static String loadError = null;

    static {
        try {
            loadNativeLibrary();
            loaded = true;
        } catch (UnsatisfiedLinkError | IOException e) {
            loadError = e.getMessage();
            loaded = false;
        }
    }

    /**
     * Check if native library is available
     */
    public static boolean isAvailable() {
        return loaded;
    }

    /**
     * Get the error message if native library failed to load
     */
    public static String getLoadError() {
        return loadError;
    }

    /**
     * Load the native library from resources or system path
     */
    private static void loadNativeLibrary() throws IOException {
        String osName = System.getProperty("os.name").toLowerCase();
        String osArch = System.getProperty("os.arch").toLowerCase();

        String libName;
        String libExtension;

        if (osName.contains("linux")) {
            libName = "libzsv_jni";
            libExtension = ".so";
        } else if (osName.contains("mac") || osName.contains("darwin")) {
            libName = "libzsv_jni";
            libExtension = ".dylib";
        } else if (osName.contains("win")) {
            libName = "zsv_jni";
            libExtension = ".dll";
        } else {
            throw new UnsatisfiedLinkError("Unsupported OS: " + osName);
        }

        // Try to load from java.library.path first
        try {
            System.loadLibrary("zsv_jni");
            return;
        } catch (UnsatisfiedLinkError e) {
            // Continue to try embedded library
        }

        // Try to extract from JAR resources
        String resourcePath = "/native/" + osName + "/" + osArch + "/" + libName + libExtension;
        InputStream is = ZsvNative.class.getResourceAsStream(resourcePath);

        if (is == null) {
            throw new UnsatisfiedLinkError(
                "Native library not found in resources: " + resourcePath +
                ". Please ensure zsv_jni is built for your platform."
            );
        }

        // Extract to temp file and load
        File tempFile = File.createTempFile("zsv_jni", libExtension);
        tempFile.deleteOnExit();
        Files.copy(is, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
        is.close();

        System.load(tempFile.getAbsolutePath());
    }

    // Native methods - these are implemented in C via JNI

    /**
     * Create a new zsv parser from file path
     * @param path Path to CSV file
     * @param delimiter Field delimiter character
     * @return Native parser handle (pointer)
     */
    public static native long createParserFromPath(String path, char delimiter);

    /**
     * Create a new zsv parser from string data
     * @param data CSV data as string
     * @param delimiter Field delimiter character
     * @return Native parser handle (pointer)
     */
    public static native long createParserFromString(String data, char delimiter);

    /**
     * Parse the next row
     * @param handle Parser handle
     * @return Array of cell values, or null if EOF
     */
    public static native String[] parseNextRow(long handle);

    /**
     * Close and free the parser
     * @param handle Parser handle
     */
    public static native void closeParser(long handle);

    /**
     * Rewind the parser to the beginning
     * @param handle Parser handle
     * @return true if successful, false otherwise
     */
    public static native boolean rewindParser(long handle);

    /**
     * Get the zsv library version
     * @return Version string
     */
    public static native String getVersion();
}
