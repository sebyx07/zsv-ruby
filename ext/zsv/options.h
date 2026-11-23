/* Options parsing and conversion */
#ifndef ZSV_RUBY_OPTIONS_H
#define ZSV_RUBY_OPTIONS_H

#include "common.h"

/* Longest row (bytes, without its line ending) parsed by default */
#define ZSV_RUBY_DEFAULT_MAX_ROW_SIZE (256 * 1024)

/* Parser options structure */
typedef struct {
    char delimiter;
    bool headers;
    VALUE header_array; /* Custom headers as Ruby array (marked by the parser) */
    int skip_lines;
    rb_encoding *encoding;
    size_t buffer_size;    /* Requested read size; the zsv buffer may be larger */
    unsigned max_columns;  /* Most fields in a row; a wider row raises */
    unsigned max_row_size; /* Most bytes in a row; a longer row raises */
} zsv_ruby_options_t;

/* Initialize options with defaults */
void zsv_options_init(zsv_ruby_options_t *opts);

/* Parse Ruby hash into options structure (raises on invalid options) */
void zsv_options_parse(VALUE opts_hash, zsv_ruby_options_t *opts);

#endif /* ZSV_RUBY_OPTIONS_H */
