// JNI wrapper for zsv C library
// This provides native bindings to the zsv SIMD-accelerated CSV parser

package zsv;

/**
 * Native JNI wrapper for the zsv C library.
 * Provides SIMD-accelerated CSV parsing for JRuby.
 */
public class ZsvNative {
    private static boolean available = false;
    private static String loadError = null;

    /**
     * Load native library from the specified path.
     * This must be called before any native methods are used.
     * The library is loaded using this class's class loader.
     *
     * @param path Absolute path to the native library
     * @return true if loading succeeded
     */
    public static synchronized boolean loadLibrary(String path) {
        if (available) {
            return true;
        }

        try {
            System.load(path);
            // Verify native methods work
            getVersion();
            available = true;
            loadError = null;
            return true;
        } catch (UnsatisfiedLinkError e) {
            available = false;
            loadError = e.getMessage();
            return false;
        }
    }

    /**
     * Load native library by name from java.library.path.
     *
     * @param name Library name (without lib prefix or extension)
     * @return true if loading succeeded
     */
    public static synchronized boolean loadLibraryByName(String name) {
        if (available) {
            return true;
        }

        try {
            System.loadLibrary(name);
            // Verify native methods work
            getVersion();
            available = true;
            loadError = null;
            return true;
        } catch (UnsatisfiedLinkError e) {
            available = false;
            loadError = e.getMessage();
            return false;
        }
    }

    /**
     * Check if native library is available
     */
    public static boolean isAvailable() {
        return available;
    }

    /**
     * Get the error message if native library failed to load
     */
    public static String getLoadError() {
        return loadError;
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
