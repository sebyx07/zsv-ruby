/* JNI wrapper for zsv C library
 * Provides native bindings for the Java ZsvNative class
 */

#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zsv.h>

/* Parser context structure */
typedef struct {
    zsv_parser zsv;
    FILE *file;
    char *data;
    size_t data_len;
    char delimiter;

    /* Row buffer */
    char **cells;
    size_t *cell_lens;
    size_t cell_count;
    size_t cell_capacity;

    /* State */
    int row_ready;
    int eof_reached;
} jni_parser_t;

/* Row callback - called by zsv for each row */
static void row_handler(void *ctx)
{
    jni_parser_t *parser = (jni_parser_t *)ctx;

    /* Reset cell count */
    parser->cell_count = 0;

    /* Get all cells */
    size_t count = zsv_cell_count(parser->zsv);

    /* Ensure capacity */
    if (count > parser->cell_capacity) {
        size_t new_cap = count * 2;
        parser->cells = realloc(parser->cells, new_cap * sizeof(char *));
        parser->cell_lens = realloc(parser->cell_lens, new_cap * sizeof(size_t));
        parser->cell_capacity = new_cap;
    }

    /* Copy cell data */
    for (size_t i = 0; i < count; i++) {
        struct zsv_cell cell = zsv_get_cell(parser->zsv, i);

        /* Allocate and copy cell data */
        parser->cells[i] = malloc(cell.len + 1);
        if (cell.len > 0) {
            memcpy(parser->cells[i], cell.str, cell.len);
        }
        parser->cells[i][cell.len] = '\0';
        parser->cell_lens[i] = cell.len;
    }

    parser->cell_count = count;
    parser->row_ready = 1;
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

    parser->delimiter = (char)delimiter;
    parser->cell_capacity = 32;
    parser->cells = malloc(parser->cell_capacity * sizeof(char *));
    parser->cell_lens = malloc(parser->cell_capacity * sizeof(size_t));

    /* Initialize zsv */
    struct zsv_opts opts = {0};
    opts.delimiter = parser->delimiter;
    opts.row_handler = row_handler;
    opts.ctx = parser;
    opts.stream = parser->file;

    parser->zsv = zsv_new(&opts);
    if (!parser->zsv) {
        fclose(parser->file);
        free(parser->cells);
        free(parser->cell_lens);
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

    parser->delimiter = (char)delimiter;
    parser->cell_capacity = 32;
    parser->cells = malloc(parser->cell_capacity * sizeof(char *));
    parser->cell_lens = malloc(parser->cell_capacity * sizeof(size_t));

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
        free(parser->cells);
        free(parser->cell_lens);
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
    if (!parser || parser->eof_reached) {
        return NULL;
    }

    /* Reset row ready flag */
    parser->row_ready = 0;

    /* Free previous row cells */
    for (size_t i = 0; i < parser->cell_count; i++) {
        free(parser->cells[i]);
        parser->cells[i] = NULL;
    }

    /* Parse until we get a row or EOF */
    while (!parser->row_ready && !parser->eof_reached) {
        enum zsv_status status = zsv_parse_more(parser->zsv);

        if (status == zsv_status_no_more_input) {
            /* Call finish to flush any pending row */
            zsv_finish(parser->zsv);
            parser->eof_reached = 1;
            break;
        } else if (status != zsv_status_ok) {
            /* Error */
            return NULL;
        }
    }

    if (!parser->row_ready) {
        return NULL;
    }

    /* Create Java String array */
    jclass stringClass = (*env)->FindClass(env, "java/lang/String");
    jobjectArray result = (*env)->NewObjectArray(env, parser->cell_count, stringClass, NULL);

    for (size_t i = 0; i < parser->cell_count; i++) {
        jstring str = (*env)->NewStringUTF(env, parser->cells[i]);
        (*env)->SetObjectArrayElement(env, result, i, str);
        (*env)->DeleteLocalRef(env, str);
    }

    return result;
}

/* Close parser */
JNIEXPORT void JNICALL Java_zsv_ZsvNative_closeParser(JNIEnv *env, jclass cls, jlong handle)
{
    (void)env;
    (void)cls;

    jni_parser_t *parser = (jni_parser_t *)(intptr_t)handle;
    if (!parser)
        return;

    /* Free cells */
    for (size_t i = 0; i < parser->cell_count; i++) {
        free(parser->cells[i]);
    }
    free(parser->cells);
    free(parser->cell_lens);

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

    /* Rewind file */
    rewind(parser->file);

    /* Recreate zsv parser */
    if (parser->zsv) {
        zsv_finish(parser->zsv);
        zsv_delete(parser->zsv);
    }

    struct zsv_opts opts = {0};
    opts.delimiter = parser->delimiter;
    opts.row_handler = row_handler;
    opts.ctx = parser;
    opts.stream = parser->file;

    parser->zsv = zsv_new(&opts);
    parser->eof_reached = 0;
    parser->row_ready = 0;

    /* Free cells */
    for (size_t i = 0; i < parser->cell_count; i++) {
        free(parser->cells[i]);
        parser->cells[i] = NULL;
    }
    parser->cell_count = 0;

    return parser->zsv ? JNI_TRUE : JNI_FALSE;
}

/* Get version */
JNIEXPORT jstring JNICALL Java_zsv_ZsvNative_getVersion(JNIEnv *env, jclass cls)
{
    (void)cls;
    return (*env)->NewStringUTF(env, "1.3.0");
}
