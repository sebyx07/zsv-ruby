/* JNI wrapper for zsv C library
 * Provides native bindings for the Java ZsvNative class
 */

#include <jni.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zsv.h>

/* Single row structure */
typedef struct {
    char **cells;
    size_t *cell_lens;
    size_t cell_count;
} jni_row_t;

/* Row buffer - dynamic array of rows */
typedef struct {
    jni_row_t *rows;
    size_t count;
    size_t capacity;
    size_t read_index; /* Index of next row to return */
} jni_row_buffer_t;

/* Parser context structure */
typedef struct {
    zsv_parser zsv;
    FILE *file;
    char *data;
    size_t data_len;
    char delimiter;

    /* Row buffer */
    jni_row_buffer_t buffer;

    /* State */
    int eof_reached;
} jni_parser_t;

/* Free a single row */
static void free_row(jni_row_t *row)
{
    if (row->cells) {
        for (size_t i = 0; i < row->cell_count; i++) {
            free(row->cells[i]);
        }
        free(row->cells);
        free(row->cell_lens);
    }
    row->cells = NULL;
    row->cell_lens = NULL;
    row->cell_count = 0;
}

/* Row callback - called by zsv for each row */
static void row_handler(void *ctx)
{
    jni_parser_t *parser = (jni_parser_t *)ctx;
    jni_row_buffer_t *buf = &parser->buffer;

    /* Ensure buffer capacity */
    if (buf->count >= buf->capacity) {
        size_t new_cap = buf->capacity == 0 ? 16 : buf->capacity * 2;
        buf->rows = realloc(buf->rows, new_cap * sizeof(jni_row_t));
        /* Initialize new slots */
        for (size_t i = buf->capacity; i < new_cap; i++) {
            memset(&buf->rows[i], 0, sizeof(jni_row_t));
        }
        buf->capacity = new_cap;
    }

    /* Get current row slot */
    jni_row_t *row = &buf->rows[buf->count];

    /* Get all cells from zsv */
    size_t count = zsv_cell_count(parser->zsv);

    /* Allocate cell arrays */
    row->cells = malloc(count * sizeof(char *));
    row->cell_lens = malloc(count * sizeof(size_t));
    row->cell_count = count;

    /* Copy cell data */
    for (size_t i = 0; i < count; i++) {
        struct zsv_cell cell = zsv_get_cell(parser->zsv, i);

        row->cells[i] = malloc(cell.len + 1);
        if (cell.len > 0) {
            memcpy(row->cells[i], cell.str, cell.len);
        }
        row->cells[i][cell.len] = '\0';
        row->cell_lens[i] = cell.len;
    }

    buf->count++;
}

/* Initialize parser common parts */
static void init_parser_common(jni_parser_t *parser, char delimiter)
{
    parser->delimiter = delimiter;
    parser->buffer.rows = NULL;
    parser->buffer.count = 0;
    parser->buffer.capacity = 0;
    parser->buffer.read_index = 0;
    parser->eof_reached = 0;
}

/* Create parser from file */
JNIEXPORT jlong JNICALL Java_zsv_ZsvNative_createParserFromPath(JNIEnv *env, jclass cls,
                                                                jstring path, jchar delimiter)
{
    (void)cls;

    const char *path_str = (*env)->GetStringUTFChars(env, path, NULL);
    if (!path_str)
        return 0;

    jni_parser_t *parser = calloc(1, sizeof(jni_parser_t));
    if (!parser) {
        (*env)->ReleaseStringUTFChars(env, path, path_str);
        return 0;
    }

    parser->file = fopen(path_str, "rb");
    (*env)->ReleaseStringUTFChars(env, path, path_str);

    if (!parser->file) {
        free(parser);
        return 0;
    }

    init_parser_common(parser, (char)delimiter);

    /* Initialize zsv */
    struct zsv_opts opts = {0};
    opts.delimiter = parser->delimiter;
    opts.row_handler = row_handler;
    opts.ctx = parser;
    opts.stream = parser->file;

    parser->zsv = zsv_new(&opts);
    if (!parser->zsv) {
        fclose(parser->file);
        free(parser);
        return 0;
    }

    return (jlong)(intptr_t)parser;
}

/* Create parser from string */
JNIEXPORT jlong JNICALL Java_zsv_ZsvNative_createParserFromString(JNIEnv *env, jclass cls,
                                                                  jstring data, jchar delimiter)
{
    (void)cls;

    const char *data_str = (*env)->GetStringUTFChars(env, data, NULL);
    if (!data_str)
        return 0;

    size_t data_len = strlen(data_str);

    jni_parser_t *parser = calloc(1, sizeof(jni_parser_t));
    if (!parser) {
        (*env)->ReleaseStringUTFChars(env, data, data_str);
        return 0;
    }

    /* Copy data */
    parser->data = malloc(data_len + 1);
    memcpy(parser->data, data_str, data_len + 1);
    parser->data_len = data_len;
    (*env)->ReleaseStringUTFChars(env, data, data_str);

    /* Create memory stream */
    parser->file = fmemopen(parser->data, parser->data_len, "rb");
    if (!parser->file) {
        free(parser->data);
        free(parser);
        return 0;
    }

    init_parser_common(parser, (char)delimiter);

    /* Initialize zsv */
    struct zsv_opts opts = {0};
    opts.delimiter = parser->delimiter;
    opts.row_handler = row_handler;
    opts.ctx = parser;
    opts.stream = parser->file;

    parser->zsv = zsv_new(&opts);
    if (!parser->zsv) {
        fclose(parser->file);
        free(parser->data);
        free(parser);
        return 0;
    }

    return (jlong)(intptr_t)parser;
}

/* Parse next row */
JNIEXPORT jobjectArray JNICALL Java_zsv_ZsvNative_parseNextRow(JNIEnv *env, jclass cls,
                                                               jlong handle)
{
    (void)cls;

    jni_parser_t *parser = (jni_parser_t *)(intptr_t)handle;
    if (!parser) {
        return NULL;
    }

    jni_row_buffer_t *buf = &parser->buffer;

    /* If we have buffered rows, return the next one */
    if (buf->read_index < buf->count) {
        jni_row_t *row = &buf->rows[buf->read_index];

        /* Create Java String array */
        jclass stringClass = (*env)->FindClass(env, "java/lang/String");
        jobjectArray result = (*env)->NewObjectArray(env, row->cell_count, stringClass, NULL);

        for (size_t i = 0; i < row->cell_count; i++) {
            jstring str = (*env)->NewStringUTF(env, row->cells[i]);
            (*env)->SetObjectArrayElement(env, result, i, str);
            (*env)->DeleteLocalRef(env, str);
        }

        /* Free this row's data and advance */
        free_row(row);
        buf->read_index++;

        return result;
    }

    /* No buffered rows - need to parse more */
    if (parser->eof_reached) {
        return NULL;
    }

    /* Reset buffer for reuse */
    buf->count = 0;
    buf->read_index = 0;

    /* Parse more data - this will call row_handler multiple times */
    enum zsv_status status = zsv_parse_more(parser->zsv);

    if (status == zsv_status_no_more_input) {
        /* Call finish to flush any pending row */
        zsv_finish(parser->zsv);
        parser->eof_reached = 1;
    } else if (status != zsv_status_ok) {
        /* Error */
        return NULL;
    }

    /* Check if we got any rows */
    if (buf->count > 0) {
        /* Return the first row */
        jni_row_t *row = &buf->rows[0];

        jclass stringClass = (*env)->FindClass(env, "java/lang/String");
        jobjectArray result = (*env)->NewObjectArray(env, row->cell_count, stringClass, NULL);

        for (size_t i = 0; i < row->cell_count; i++) {
            jstring str = (*env)->NewStringUTF(env, row->cells[i]);
            (*env)->SetObjectArrayElement(env, result, i, str);
            (*env)->DeleteLocalRef(env, str);
        }

        /* Free this row's data and advance */
        free_row(row);
        buf->read_index = 1;

        return result;
    }

    return NULL;
}

/* Close parser */
JNIEXPORT void JNICALL Java_zsv_ZsvNative_closeParser(JNIEnv *env, jclass cls, jlong handle)
{
    (void)env;
    (void)cls;

    jni_parser_t *parser = (jni_parser_t *)(intptr_t)handle;
    if (!parser)
        return;

    /* Free all buffered rows */
    for (size_t i = 0; i < parser->buffer.count; i++) {
        free_row(&parser->buffer.rows[i]);
    }
    free(parser->buffer.rows);

    /* Cleanup zsv */
    if (parser->zsv) {
        zsv_delete(parser->zsv);
    }

    if (parser->file) {
        fclose(parser->file);
    }

    if (parser->data) {
        free(parser->data);
    }

    free(parser);
}

/* Rewind parser */
JNIEXPORT jboolean JNICALL Java_zsv_ZsvNative_rewindParser(JNIEnv *env, jclass cls, jlong handle)
{
    (void)env;
    (void)cls;

    jni_parser_t *parser = (jni_parser_t *)(intptr_t)handle;
    if (!parser || !parser->file) {
        return JNI_FALSE;
    }

    /* Delete old zsv parser first (don't call finish - we're abandoning it) */
    if (parser->zsv) {
        zsv_delete(parser->zsv);
        parser->zsv = NULL;
    }

    /* Clear buffer */
    for (size_t i = parser->buffer.read_index; i < parser->buffer.count; i++) {
        free_row(&parser->buffer.rows[i]);
    }
    parser->buffer.count = 0;
    parser->buffer.read_index = 0;

    /* Rewind file */
    rewind(parser->file);

    /* Recreate zsv parser */
    struct zsv_opts opts = {0};
    opts.delimiter = parser->delimiter;
    opts.row_handler = row_handler;
    opts.ctx = parser;
    opts.stream = parser->file;

    parser->zsv = zsv_new(&opts);
    parser->eof_reached = 0;

    return parser->zsv ? JNI_TRUE : JNI_FALSE;
}

/* Get version */
JNIEXPORT jstring JNICALL Java_zsv_ZsvNative_getVersion(JNIEnv *env, jclass cls)
{
    (void)cls;
    return (*env)->NewStringUTF(env, "1.3.0");
}
