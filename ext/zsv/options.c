/* Options parsing and conversion implementation */
#include "options.h"
#include "options_internal.h"

/* Symbol constants for option keys */
static ID id_headers;
static ID id_col_sep;
static ID id_quote_char;
static ID id_skip_lines;
static ID id_encoding;
static ID id_buffer_size;
static ID id_max_columns;
static ID id_max_row_size;

void zsv_options_init(zsv_ruby_options_t *opts)
{
    opts->delimiter = ',';
    opts->headers = false;
    opts->header_array = Qnil;
    opts->skip_lines = 0;
    opts->encoding = rb_utf8_encoding();
    opts->buffer_size = ZSV_DEFAULT_SCANNER_BUFFSIZE;
    opts->max_columns = ZSV_MAX_COLS_DEFAULT;
    opts->max_row_size = ZSV_RUBY_DEFAULT_MAX_ROW_SIZE;
}

static VALUE get_option(VALUE opts_hash, ID key)
{
    return rb_hash_lookup(opts_hash, ID2SYM(key));
}

static char parse_single_char(VALUE value, const char *name)
{
    StringValue(value);
    if (RSTRING_LEN(value) != 1) {
        rb_raise(rb_eArgError, "%s must be a single character", name);
    }
    return RSTRING_PTR(value)[0];
}

static unsigned parse_positive_uint(VALUE value, const char *name)
{
    unsigned long n = NUM2ULONG(value);
    if (n == 0 || n > UINT_MAX) {
        rb_raise(rb_eArgError, "%s must be between 1 and %u", name, UINT_MAX);
    }
    return (unsigned)n;
}

void zsv_options_parse(VALUE opts_hash, zsv_ruby_options_t *opts)
{
    zsv_options_init(opts);

    if (NIL_P(opts_hash)) {
        return;
    }

    Check_Type(opts_hash, T_HASH);

    VALUE col_sep = get_option(opts_hash, id_col_sep);
    if (!NIL_P(col_sep)) {
        opts->delimiter = parse_single_char(col_sep, "col_sep");
        /* zsv silently replaces these delimiters with ',' */
        if (opts->delimiter == '\n' || opts->delimiter == '\r' || opts->delimiter == '"') {
            rb_raise(rb_eArgError, "col_sep cannot be a newline or a double quote");
        }
    }

    /* zsv only supports '"' as the quote character */
    VALUE quote_char = get_option(opts_hash, id_quote_char);
    if (!NIL_P(quote_char) && parse_single_char(quote_char, "quote_char") != '"') {
        rb_raise(rb_eArgError, "quote_char must be '\"' (zsv does not support other quotes)");
    }

    VALUE headers = get_option(opts_hash, id_headers);
    if (RB_TYPE_P(headers, T_ARRAY)) {
        opts->headers = true;
        opts->header_array = headers;
    } else {
        opts->headers = RTEST(headers);
    }

    VALUE skip_lines = get_option(opts_hash, id_skip_lines);
    if (!NIL_P(skip_lines)) {
        opts->skip_lines = NUM2INT(skip_lines);
        if (opts->skip_lines < 0) {
            rb_raise(rb_eArgError, "skip_lines must not be negative");
        }
    }

    VALUE encoding = get_option(opts_hash, id_encoding);
    if (!NIL_P(encoding)) {
        opts->encoding = rb_to_encoding(encoding);
    }

    VALUE buffer_size = get_option(opts_hash, id_buffer_size);
    if (!NIL_P(buffer_size)) {
        opts->buffer_size = NUM2SIZET(buffer_size);
        if (opts->buffer_size == 0) {
            rb_raise(rb_eArgError, "buffer_size must be positive");
        }
    }

    VALUE max_columns = get_option(opts_hash, id_max_columns);
    if (!NIL_P(max_columns)) {
        opts->max_columns = parse_positive_uint(max_columns, "max_columns");
    }

    VALUE max_row_size = get_option(opts_hash, id_max_row_size);
    if (!NIL_P(max_row_size)) {
        opts->max_row_size = parse_positive_uint(max_row_size, "max_row_size");
    }
}

/* Initialize symbols (call from Init_zsv) */
void Init_zsv_options(void)
{
    id_headers = rb_intern("headers");
    id_col_sep = rb_intern("col_sep");
    id_quote_char = rb_intern("quote_char");
    id_skip_lines = rb_intern("skip_lines");
    id_encoding = rb_intern("encoding");
    id_buffer_size = rb_intern("buffer_size");
    id_max_columns = rb_intern("max_columns");
    id_max_row_size = rb_intern("max_row_size");
}
