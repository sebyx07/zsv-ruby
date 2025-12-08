// High-level Java parser wrapper for zsv
// This is used by JRuby to provide the same API as the C extension

package zsv;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * CSV Parser that uses zsv native library when available,
 * with a pure Java fallback implementation.
 */
public class ZsvParser {
    private long nativeHandle = 0;
    private boolean closed = false;
    private boolean eofReached = false;
    private char delimiter = ',';
    private char quoteChar = '"';
    private boolean useHeaders = false;
    private String[] headers = null;
    private String[] customHeaders = null;
    private int skipLines = 0;
    private int linesSkipped = 0;
    private boolean headerRowProcessed = false;

    // For pure Java fallback
    private BufferedReader reader = null;
    private String csvData = null;
    private String filePath = null;
    private boolean useNative = false;

    /**
     * Create parser from file path
     */
    public ZsvParser(String path, Map<String, Object> options) throws IOException {
        this.filePath = path;
        parseOptions(options);

        if (ZsvNative.isAvailable()) {
            this.nativeHandle = ZsvNative.createParserFromPath(path, delimiter);
            this.useNative = true;
        } else {
            this.reader = new BufferedReader(new FileReader(path));
            this.useNative = false;
        }
    }

    /**
     * Create parser from string data (static factory method)
     */
    public static ZsvParser fromString(String data, Map<String, Object> options) {
        ZsvParser parser = new ZsvParser();
        parser.csvData = data;
        parser.parseOptions(options);

        if (ZsvNative.isAvailable()) {
            parser.nativeHandle = ZsvNative.createParserFromString(data, parser.delimiter);
            parser.useNative = true;
        } else {
            parser.reader = new BufferedReader(new StringReader(data));
            parser.useNative = false;
        }

        return parser;
    }

    // Private constructor for factory methods
    private ZsvParser() {}

    /**
     * Parse options from map
     */
    private void parseOptions(Map<String, Object> options) {
        if (options == null) return;

        if (options.containsKey("col_sep")) {
            String sep = options.get("col_sep").toString();
            if (sep.length() > 0) {
                this.delimiter = sep.charAt(0);
            }
        }

        if (options.containsKey("quote_char")) {
            String qc = options.get("quote_char").toString();
            if (qc.length() > 0) {
                this.quoteChar = qc.charAt(0);
            }
        }

        if (options.containsKey("headers")) {
            Object h = options.get("headers");
            if (h instanceof Boolean) {
                this.useHeaders = (Boolean) h;
            } else if (h instanceof String[]) {
                this.useHeaders = true;
                this.customHeaders = (String[]) h;
                this.headerRowProcessed = true;
                this.headers = this.customHeaders;
            } else if (h instanceof List) {
                this.useHeaders = true;
                List<?> list = (List<?>) h;
                this.customHeaders = list.toArray(new String[0]);
                this.headerRowProcessed = true;
                this.headers = this.customHeaders;
            }
        }

        if (options.containsKey("skip_lines")) {
            Object sl = options.get("skip_lines");
            if (sl instanceof Number) {
                this.skipLines = ((Number) sl).intValue();
            }
        }
    }

    /**
     * Read and return the next row as array
     * @return Array of cell values, or null if EOF
     */
    public String[] shift() throws IOException {
        if (closed || eofReached) {
            return null;
        }

        String[] row;

        if (useNative) {
            row = shiftNative();
        } else {
            row = shiftPureJava();
        }

        if (row == null) {
            eofReached = true;
            return null;
        }

        // Skip lines if configured
        if (linesSkipped < skipLines) {
            linesSkipped++;
            return shift(); // Recursive call to get next row
        }

        // Process header row if needed
        if (useHeaders && customHeaders == null && !headerRowProcessed) {
            headers = row;
            headerRowProcessed = true;
            return shift(); // Recursive call to get first data row
        }

        return row;
    }

    /**
     * Read next row using native library
     */
    private String[] shiftNative() {
        if (nativeHandle == 0) {
            return null;
        }
        return ZsvNative.parseNextRow(nativeHandle);
    }

    /**
     * Read next row using pure Java implementation
     */
    private String[] shiftPureJava() throws IOException {
        if (reader == null) {
            return null;
        }

        String line = reader.readLine();
        if (line == null) {
            return null;
        }

        return parseLine(line);
    }

    /**
     * Parse a CSV line into fields (pure Java fallback)
     */
    private String[] parseLine(String line) throws IOException {
        List<String> fields = new ArrayList<>();
        StringBuilder field = new StringBuilder();
        boolean inQuotes = false;

        int i = 0;
        while (i < line.length()) {
            char c = line.charAt(i);

            if (inQuotes) {
                if (c == quoteChar) {
                    if (i + 1 < line.length() && line.charAt(i + 1) == quoteChar) {
                        // Escaped quote
                        field.append(quoteChar);
                        i += 2;
                    } else {
                        // End of quoted field
                        inQuotes = false;
                        i++;
                    }
                } else if (c == '\r' || (c == '\n' && i + 1 < line.length())) {
                    // Newline inside quotes - need to read more
                    field.append(c);
                    i++;
                } else {
                    field.append(c);
                    i++;
                }
            } else {
                if (c == quoteChar) {
                    inQuotes = true;
                    i++;
                } else if (c == delimiter) {
                    fields.add(field.toString());
                    field = new StringBuilder();
                    i++;
                } else {
                    field.append(c);
                    i++;
                }
            }
        }

        // Handle multiline fields (quotes spanning lines)
        if (inQuotes && reader != null) {
            String nextLine = reader.readLine();
            if (nextLine != null) {
                field.append('\n');
                String[] rest = parseLine(field.toString() + nextLine);
                // Merge with existing fields
                String[] result = new String[fields.size() + rest.length];
                for (int j = 0; j < fields.size(); j++) {
                    result[j] = fields.get(j);
                }
                for (int j = 0; j < rest.length; j++) {
                    result[fields.size() + j] = rest[j];
                }
                return result;
            }
        }

        fields.add(field.toString());
        return fields.toArray(new String[0]);
    }

    /**
     * Read next row as hash (if headers enabled)
     * @return Map with header keys and cell values, or null if EOF
     */
    public Map<String, String> shiftAsHash() throws IOException {
        String[] row = shift();
        if (row == null || headers == null) {
            return null;
        }

        Map<String, String> result = new HashMap<>();
        for (int i = 0; i < headers.length && i < row.length; i++) {
            result.put(headers[i], row[i]);
        }
        // Handle extra columns with numeric keys
        for (int i = headers.length; i < row.length; i++) {
            result.put(String.valueOf(i), row[i]);
        }

        return result;
    }

    /**
     * Get headers (if enabled)
     */
    public String[] getHeaders() {
        return headers;
    }

    /**
     * Check if headers are enabled
     */
    public boolean hasHeaders() {
        return useHeaders && headers != null;
    }

    /**
     * Rewind parser to beginning
     */
    public void rewind() throws IOException {
        if (useNative && nativeHandle != 0) {
            ZsvNative.rewindParser(nativeHandle);
        } else if (filePath != null) {
            if (reader != null) {
                reader.close();
            }
            reader = new BufferedReader(new FileReader(filePath));
        } else if (csvData != null) {
            reader = new BufferedReader(new StringReader(csvData));
        }

        eofReached = false;
        linesSkipped = 0;
        if (customHeaders == null) {
            headerRowProcessed = false;
            headers = null;
        }
    }

    /**
     * Close the parser
     */
    public void close() throws IOException {
        if (closed) return;

        closed = true;

        if (useNative && nativeHandle != 0) {
            ZsvNative.closeParser(nativeHandle);
            nativeHandle = 0;
        }

        if (reader != null) {
            reader.close();
            reader = null;
        }
    }

    /**
     * Check if parser is closed
     */
    public boolean isClosed() {
        return closed;
    }

    /**
     * Check if native library is being used
     */
    public boolean isUsingNative() {
        return useNative;
    }
}
