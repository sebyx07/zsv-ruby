/* Parser wrapper implementation using zsv's callback API
 *
 * zsv pushes rows into zsv_row_handler() from inside zsv_parse_more(). Ruby
 * code that can raise (allocation, Hash#[]= on custom header objects, IO#read)
 * therefore runs below zsv's C frames. A longjmp through those frames would
 * leave zsv half-way through a buffer, so every callback runs its Ruby code
 * under rb_protect(), records the jump state, and returns normally; the
 * exception is re-raised once control is back in our code, after the parser
 * has been closed.
 *
 * Row size: zsv holds a row in one buffer and, when a row fills it, warns
 * through errprintf and hands the row on cut short. The buffer is therefore
 * sized to hold any row of max_row_size bytes, the row handler raises for a
 * longer one, and the truncation warning raises too, so no row is ever
 * returned incomplete. zsv's overflow_row_handler is not used: zsv 1.4.4 calls
 * it with its own scanner as the context instead of ours. */
#include "parser.h"
#include <string.h>

static ID id_read;
static ID id_rewind;

static void zsv_parser_create_zsv(zsv_ruby_parser_t *parser);

void zsv_parser_init_struct(zsv_ruby_parser_t *parser)
{
    memset(parser, 0, sizeof(*parser));
    parser->source = Qnil;
    parser->row_buffer = Qnil;
    parser->headers = Qnil;
    zsv_options_init(&parser->options);
}

/* ---- GC support ---------------------------------------------------------- */

/* The zsv buffer: the requested read size, but always room for a row of
 * max_row_size bytes plus the byte that ends it. zsv only cuts a row short
 * when the row alone fills the buffer. */
static size_t zsv_parser_buffer_size(const zsv_ruby_options_t *options)
{
    size_t row_buffer = (size_t)options->max_row_size + 1;
    if (row_buffer == 0) { /* 32-bit size_t and max_row_size == UINT_MAX */
        row_buffer = SIZE_MAX;
    }
    return options->buffer_size > row_buffer ? options->buffer_size : row_buffer;
}

void zsv_parser_mark(zsv_ruby_parser_t *parser)
{
    rb_gc_mark_movable(parser->source);
    rb_gc_mark_movable(parser->row_buffer);
    rb_gc_mark_movable(parser->headers);
    rb_gc_mark_movable(parser->options.header_array);
    if (parser->row_builder) {
        zsv_row_builder_mark(parser->row_builder);
    }
}

void zsv_parser_compact(zsv_ruby_parser_t *parser)
{
    parser->source = rb_gc_location(parser->source);
    parser->row_buffer = rb_gc_location(parser->row_buffer);
    parser->headers = rb_gc_location(parser->headers);
    parser->options.header_array = rb_gc_location(parser->options.header_array);
    if (parser->row_builder) {
        zsv_row_builder_compact(parser->row_builder);
    }
}

size_t zsv_parser_memsize(const zsv_ruby_parser_t *parser)
{
    size_t size = sizeof(*parser);
    if (parser->row_builder) {
        size += zsv_row_builder_memsize(parser->row_builder);
    }
    if (parser->zsv) {
        size += zsv_parser_buffer_size(&parser->options);
    }
    return size;
}

/* ---- zsv callbacks --------------------------------------------------------- */

/* An empty unquoted line: CSV returns [] for it, not [""] */
static bool zsv_parser_blank_row(zsv_ruby_parser_t *parser, size_t cell_count)
{
    if (cell_count == 0) {
        return true;
    }
    if (cell_count != 1) {
        return false;
    }
    struct zsv_cell cell = zsv_get_cell(parser->zsv, 0);
    return cell.len == 0 && !(cell.quoted & ZSV_PARSER_QUOTE_CLOSED);
}

static void zsv_parser_build_row(zsv_ruby_parser_t *parser, size_t cell_count)
{
    zsv_row_builder_reset(parser->row_builder);
    for (size_t i = 0; i < cell_count; i++) {
        struct zsv_cell cell = zsv_get_cell(parser->zsv, i);
        zsv_row_builder_add_cell(parser->row_builder, cell.str, cell.len);
    }
}

/* Raise ZSV::MalformedCSVError for the current record; its #line_number is the
 * 1-based record, as in CSV ("... in line N.") */
static void zsv_parser_raise_malformed(zsv_ruby_parser_t *parser, VALUE message)
{
    VALUE args[2] = {message, SIZET2NUM(parser->record_count)};
    rb_exc_raise(rb_class_new_instance(2, args, eMalformedCSVError));
}

static VALUE zsv_row_handler_body(VALUE arg)
{
    zsv_ruby_parser_t *parser = (zsv_ruby_parser_t *)arg;
    parser->record_count++;

    if (parser->row_truncated ||
        zsv_row_length_raw_bytes(parser->zsv) > parser->options.max_row_size) {
        zsv_parser_raise_malformed(parser, rb_sprintf("Row longer than max_row_size (%u bytes)",
                                                      parser->options.max_row_size));
    }
    if (parser->column_overflow) {
        zsv_parser_raise_malformed(parser, rb_sprintf("Row with more than max_columns (%u) fields",
                                                      parser->options.max_columns));
    }

    /* Skip lines if configured */
    if (parser->lines_skipped < (size_t)parser->options.skip_lines) {
        parser->lines_skipped++;
        return Qnil;
    }

    size_t cell_count = zsv_cell_count(parser->zsv);
    bool blank = zsv_parser_blank_row(parser, cell_count);

    /* Header row - only if headers: true and no custom headers provided.
     * Blank lines before it are skipped. */
    if (parser->options.headers && !parser->header_row_processed) {
        if (blank) {
            return Qnil;
        }
        zsv_parser_build_row(parser, cell_count);
        parser->headers = zsv_row_builder_to_array(parser->row_builder);
        zsv_row_builder_set_headers(parser->row_builder, parser->headers);
        parser->header_row_processed = true;
        return Qnil;
    }

    zsv_parser_build_row(parser, blank ? 0 : cell_count);

    VALUE row = NIL_P(parser->headers) ? zsv_row_builder_to_array(parser->row_builder)
                                       : zsv_row_builder_to_hash(parser->row_builder);
    rb_ary_push(parser->row_buffer, row);
    return Qnil;
}

static void zsv_row_handler(void *ctx)
{
    zsv_ruby_parser_t *parser = (zsv_ruby_parser_t *)ctx;
    if (parser->exception_state) {
        return; /* an earlier callback raised; drop the rest of this chunk */
    }
    rb_protect(zsv_row_handler_body, (VALUE)parser, &parser->exception_state);
}

/* zsv prints warnings to stderr. Silence them, and turn the two that mean
 * data loss into errors: both are printed just before the damaged row reaches
 * zsv_row_handler, which raises. */
static int zsv_errprintf(void *ctx, const char *format, ...)
{
    zsv_ruby_parser_t *parser = (zsv_ruby_parser_t *)ctx;
    if (strstr(format, "exceeds row max") != NULL) {
        parser->column_overflow = true; /* columns beyond max_columns dropped */
    } else if (strstr(format, "truncated") != NULL) {
        parser->row_truncated = true; /* a row that filled the whole buffer */
    }
    return 0;
}

static size_t zsv_string_read(void *buffer, size_t size, size_t count, void *ctx)
{
    zsv_ruby_parser_t *parser = (zsv_ruby_parser_t *)ctx;
    if (size == 0) {
        return 0;
    }

    /* The source is frozen, so its length cannot change between reads. The
     * pointer is re-read on every call because GC compaction may move it. */
    size_t length = RSTRING_LEN(parser->source);
    size_t available = length - parser->source_offset;
    size_t copied = available < size * count ? available : size * count;
    copied -= copied % size;

    memcpy(buffer, RSTRING_PTR(parser->source) + parser->source_offset, copied);
    parser->source_offset += copied;
    return copied / size;
}

typedef struct {
    zsv_ruby_parser_t *parser;
    size_t requested;
} zsv_io_read_args_t;

static VALUE zsv_io_read_chunk(VALUE arg)
{
    zsv_io_read_args_t *args = (zsv_io_read_args_t *)arg;
    VALUE io = args->parser->source;
    VALUE chunk = rb_funcall(io, id_read, 1, SIZET2NUM(args->requested));

    if (NIL_P(chunk)) {
        return Qnil;
    }
    StringValue(chunk);
    if ((size_t)RSTRING_LEN(chunk) > args->requested) {
        rb_raise(rb_eIOError, "%s#read returned more bytes than requested", rb_obj_classname(io));
    }
    return chunk;
}

static size_t zsv_io_read(void *buffer, size_t size, size_t count, void *ctx)
{
    zsv_ruby_parser_t *parser = (zsv_ruby_parser_t *)ctx;
    if (parser->exception_state || size == 0 || count == 0) {
        return 0;
    }

    zsv_io_read_args_t args = {parser, size * count};
    VALUE chunk = rb_protect(zsv_io_read_chunk, (VALUE)&args, &parser->exception_state);
    if (parser->exception_state || NIL_P(chunk)) {
        return 0; /* zsv sees EOF; the driver re-raises the exception */
    }

    size_t length = RSTRING_LEN(chunk);
    memcpy(buffer, RSTRING_PTR(chunk), length);
    RB_GC_GUARD(chunk);
    return length / size;
}

/* ---- setup ------------------------------------------------------------------ */

static void zsv_parser_create_zsv(zsv_ruby_parser_t *parser)
{
    struct zsv_opts zopts;
    memset(&zopts, 0, sizeof(zopts));

    zopts.delimiter = parser->options.delimiter;
    zopts.buffsize = zsv_parser_buffer_size(&parser->options);
    /* zsv only uses max_row_size to grow buffsize to twice its value: pass
     * half the buffer so zsv keeps ours (and its unsigned doubling cannot
     * wrap); the row limit itself is enforced by zsv_row_handler_body */
    zopts.max_row_size =
        (unsigned)(zopts.buffsize / 2 < UINT_MAX / 2 ? zopts.buffsize / 2 : UINT_MAX / 2);
    zopts.max_columns = parser->options.max_columns;
    zopts.keep_empty_header_rows = 1; /* we handle blank lines ourselves */
    zopts.row_handler = zsv_row_handler;
    zopts.ctx = parser;
    zopts.errprintf = zsv_errprintf;
    zopts.errf = parser;

    switch (parser->source_kind) {
        case ZSV_SOURCE_FILE:
            zopts.stream = parser->file; /* default reader is fread() */
            break;
        case ZSV_SOURCE_STRING:
            zopts.read = zsv_string_read;
            zopts.stream = parser;
            break;
        case ZSV_SOURCE_IO:
            zopts.read = zsv_io_read;
            zopts.stream = parser;
            break;
        case ZSV_SOURCE_NONE:
            rb_raise(eZSVError, "parser has no input source");
    }

    parser->zsv = zsv_new(&zopts);
    if (!parser->zsv) {
        parser->closed = true;
        rb_raise(rb_eNoMemError, "failed to create zsv parser");
    }
}

static void zsv_parser_reset_state(zsv_ruby_parser_t *parser)
{
    parser->record_count = 0;
    parser->lines_skipped = 0;
    parser->eof_reached = false;
    parser->column_overflow = false;
    parser->row_truncated = false;
    parser->exception_state = 0;
    parser->row_buffer = rb_ary_new();

    /* Custom headers skip the first row; otherwise it is read as the header */
    if (!NIL_P(parser->options.header_array)) {
        parser->headers = parser->options.header_array;
        parser->header_row_processed = true;
    } else {
        parser->headers = Qnil;
        parser->header_row_processed = false;
    }
    zsv_row_builder_set_headers(parser->row_builder, parser->headers);
}

/* Parse options and allocate Ruby-side state. Runs before any OS resource is
 * acquired so an invalid option cannot leak a FILE*. */
static void zsv_parser_setup(zsv_ruby_parser_t *parser, VALUE opts_hash)
{
    /* row_builder is set once setup has run, even when the open that follows
     * failed: a second initialize would otherwise leak the first builder */
    if (parser->source_kind != ZSV_SOURCE_NONE || parser->row_builder) {
        rb_raise(rb_eRuntimeError, "ZSV::Parser is already initialized");
    }

    zsv_options_parse(opts_hash, &parser->options);
    parser->row_builder = zsv_row_builder_new(parser->options.encoding);
    zsv_parser_reset_state(parser);
}

void zsv_parser_init_path(zsv_ruby_parser_t *parser, VALUE path, VALUE opts_hash)
{
    FilePathValue(path);
    zsv_parser_setup(parser, opts_hash);

    parser->file = fopen(RSTRING_PTR(path), "rb");
    RB_GC_GUARD(path);
    if (!parser->file) {
        rb_sys_fail_str(path);
    }
    parser->source_kind = ZSV_SOURCE_FILE;
    zsv_parser_create_zsv(parser);
}

void zsv_parser_init_string(zsv_ruby_parser_t *parser, VALUE string, VALUE opts_hash)
{
    StringValue(string);
    zsv_parser_setup(parser, opts_hash);

    /* A frozen copy (sharing the buffer) so mutating the caller's string
     * during the parse cannot free or change the bytes zsv is reading */
    parser->source = rb_str_new_frozen(string);
    parser->source_kind = ZSV_SOURCE_STRING;
    zsv_parser_create_zsv(parser);
}

void zsv_parser_init_io(zsv_ruby_parser_t *parser, VALUE io, VALUE opts_hash)
{
    if (!rb_respond_to(io, id_read)) {
        rb_raise(rb_eTypeError, "expected an IO-like object responding to #read, got %s",
                 rb_obj_classname(io));
    }
    zsv_parser_setup(parser, opts_hash);

    parser->source = io;
    parser->source_kind = ZSV_SOURCE_IO;
    zsv_parser_create_zsv(parser);
}

/* ---- teardown --------------------------------------------------------------- */

/* Release zsv and the FILE*. Never calls into Ruby: runs from dfree during GC. */
static void zsv_parser_release(zsv_ruby_parser_t *parser)
{
    parser->closed = true;

    if (parser->zsv) {
        zsv_delete(parser->zsv);
        parser->zsv = NULL;
    }

    if (parser->file) {
        fclose(parser->file);
        parser->file = NULL;
    }
}

void zsv_parser_free(zsv_ruby_parser_t *parser)
{
    if (!parser)
        return;

    zsv_parser_release(parser);
    zsv_row_builder_free(parser->row_builder);
    xfree(parser);
}

static void zsv_parser_ensure_not_parsing(zsv_ruby_parser_t *parser)
{
    if (parser->parsing) {
        rb_raise(eZSVError, "ZSV::Parser is in use (re-entered from a callback or another thread)");
    }
}

void zsv_parser_close(zsv_ruby_parser_t *parser)
{
    zsv_parser_ensure_not_parsing(parser);
    zsv_parser_release(parser);
}

/* ---- parsing ------------------------------------------------------------------ */

/* Feed zsv one buffer of input; at EOF flush the final row with zsv_finish(),
 * exactly once. Ruby code only runs under rb_protect() in here. */
static enum zsv_status zsv_parser_parse_chunk(zsv_ruby_parser_t *parser)
{
    parser->parsing = true;
    enum zsv_status status = zsv_parse_more(parser->zsv);
    if (status == zsv_status_no_more_input && !parser->exception_state) {
        enum zsv_status finish_status = zsv_finish(parser->zsv);
        parser->eof_reached = true;
        if (finish_status != zsv_status_ok) {
            status = finish_status;
        }
    }
    parser->parsing = false;
    return status;
}

static void zsv_parser_raise_on_error(zsv_ruby_parser_t *parser, enum zsv_status status)
{
    if (parser->exception_state) {
        int state = parser->exception_state;
        zsv_parser_release(parser);
        rb_jump_tag(state);
    }

    if (status != zsv_status_ok && status != zsv_status_no_more_input) {
        zsv_parser_release(parser);
        rb_raise(eMalformedCSVError, "CSV parsing error: %s", zsv_parse_status_desc(status));
    }
}

static void zsv_parser_fill(zsv_ruby_parser_t *parser)
{
    /* A chunk can end without completing a row (long rows, skipped or header
     * rows, no trailing newline), so keep going until a row or EOF */
    while (!parser->closed && !parser->eof_reached && RARRAY_LEN(parser->row_buffer) == 0) {
        enum zsv_status status = zsv_parser_parse_chunk(parser);
        zsv_parser_raise_on_error(parser, status);
        rb_thread_check_ints(); /* outside zsv: safe to raise Interrupt here */
    }
}

VALUE zsv_parser_shift(zsv_ruby_parser_t *parser)
{
    zsv_parser_ensure_not_parsing(parser);
    if (parser->closed) {
        return Qnil;
    }

    zsv_parser_fill(parser);

    if (!parser->closed && RARRAY_LEN(parser->row_buffer) > 0) {
        return rb_ary_shift(parser->row_buffer);
    }
    return Qnil;
}

void zsv_parser_rewind(zsv_ruby_parser_t *parser)
{
    zsv_parser_ensure_not_parsing(parser);
    if (parser->closed) {
        rb_raise(rb_eIOError, "closed parser");
    }

    switch (parser->source_kind) {
        case ZSV_SOURCE_FILE:
            if (fseek(parser->file, 0, SEEK_SET) != 0) {
                rb_sys_fail("rewind");
            }
            break;
        case ZSV_SOURCE_STRING:
            parser->source_offset = 0;
            break;
        case ZSV_SOURCE_IO:
            rb_funcall(parser->source, id_rewind, 0);
            break;
        case ZSV_SOURCE_NONE:
            rb_raise(eZSVError, "parser has no input source");
    }

    zsv_parser_reset_state(parser);
    zsv_delete(parser->zsv);
    parser->zsv = NULL;
    zsv_parser_create_zsv(parser);
}

VALUE zsv_parser_headers(zsv_ruby_parser_t *parser)
{
    return parser->headers;
}

bool zsv_parser_closed(zsv_ruby_parser_t *parser)
{
    return parser->closed;
}

void Init_zsv_parser(void)
{
    id_read = rb_intern("read");
    id_rewind = rb_intern("rewind");
}
