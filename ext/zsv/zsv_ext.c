/* Main entry point for zsv Ruby extension */
#include "common.h"
#include "options.h"
#include "options_internal.h"
#include "parser.h"
#include "row.h"

/* Module and class definitions */
VALUE mZSV = Qnil;
VALUE cParser = Qnil;
VALUE eZSVError = Qnil;
VALUE eMalformedCSVError = Qnil;
VALUE eInvalidEncodingError = Qnil;

/* GC marking function for Parser */
static void zsv_parser_mark(void *ptr)
{
    zsv_ruby_parser_t *parser = (zsv_ruby_parser_t *)ptr;
    if (!parser)
        return;

    rb_gc_mark(parser->io);
    rb_gc_mark(parser->headers);
    rb_gc_mark(parser->current_row);
    rb_gc_mark(parser->row_buffer);
    rb_gc_mark(parser->options.header_array);
}

/* GC freeing function for Parser */
static void zsv_parser_gc_free(void *ptr)
{
    zsv_parser_free((zsv_ruby_parser_t *)ptr);
}

/* Size function for GC */
static size_t zsv_parser_memsize(const void *ptr)
{
    return ptr ? sizeof(zsv_ruby_parser_t) : 0;
}

/* Data type definition */
static const rb_data_type_t zsv_parser_type = {
    .wrap_struct_name = "ZSV::Parser",
    .function =
        {
            .dmark = zsv_parser_mark,
            .dfree = zsv_parser_gc_free,
            .dsize = zsv_parser_memsize,
        },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* Unwrap parser from Ruby object */
static zsv_ruby_parser_t *get_parser(VALUE self)
{
    zsv_ruby_parser_t *parser;
    TypedData_Get_Struct(self, zsv_ruby_parser_t, &zsv_parser_type, parser);
    return parser;
}

/* Wrap parser in Ruby object */
static VALUE wrap_parser(zsv_ruby_parser_t *parser)
{
    return TypedData_Wrap_Struct(cParser, &zsv_parser_type, parser);
}

/* Allocate function for Parser class */
static VALUE zsv_parser_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &zsv_parser_type, NULL);
}

/*
 * call-seq:
 *   ZSV::Parser.new(io, **options) -> parser
 *
 * Creates a new parser for the given IO object.
 */
static VALUE rb_zsv_parser_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE io, opts;
    rb_scan_args(argc, argv, "11", &io, &opts);

    zsv_ruby_parser_t *parser;

    if (TYPE(io) == T_STRING) {
        const char *str = StringValueCStr(io);

        /* Detect if it's a file path or CSV content */
        /* If it contains newlines or commas and doesn't exist as a file, treat as CSV data */
        if (strchr(str, '\n') != NULL || strchr(str, ',') != NULL) {
            /* Looks like CSV content, parse as string */
            parser = zsv_parser_new_from_string(io, opts);
        } else {
            /* Try as file path */
            parser = zsv_parser_new_from_path(str, opts);
        }
    } else {
        /* IO object */
        parser = zsv_parser_new_from_io(io, opts);
    }

    DATA_PTR(self) = parser;
    return self;
}

/*
 * call-seq:
 *   parser.shift -> array or hash or nil
 *
 * Reads and returns the next row. Returns nil at EOF.
 */
static VALUE rb_zsv_parser_shift(VALUE self)
{
    zsv_ruby_parser_t *parser = get_parser(self);
    return zsv_parser_shift(parser);
}

/*
 * call-seq:
 *   parser.each {|row| block } -> nil
 *   parser.each -> enumerator
 *
 * Iterates over all rows.
 */
static VALUE rb_zsv_parser_each(VALUE self)
{
    RETURN_ENUMERATOR(self, 0, 0);

    zsv_ruby_parser_t *parser = get_parser(self);
    zsv_parser_each(parser);
    return Qnil;
}

/*
 * call-seq:
 *   parser.rewind -> nil
 *
 * Rewinds the parser to the beginning.
 */
static VALUE rb_zsv_parser_rewind(VALUE self)
{
    zsv_ruby_parser_t *parser = get_parser(self);
    zsv_parser_rewind(parser);
    return Qnil;
}

/*
 * call-seq:
 *   parser.close -> nil
 *
 * Closes the parser and releases resources.
 */
static VALUE rb_zsv_parser_close(VALUE self)
{
    zsv_ruby_parser_t *parser = get_parser(self);
    zsv_parser_close(parser);
    return Qnil;
}

/*
 * call-seq:
 *   parser.headers -> array or nil
 *
 * Returns the headers if header mode is enabled.
 */
static VALUE rb_zsv_parser_headers_get(VALUE self)
{
    zsv_ruby_parser_t *parser = get_parser(self);
    return zsv_parser_headers(parser);
}

/*
 * call-seq:
 *   parser.closed? -> bool
 *
 * Returns true if the parser is closed.
 */
static VALUE rb_zsv_parser_closed_p(VALUE self)
{
    zsv_ruby_parser_t *parser = get_parser(self);
    return zsv_parser_closed(parser) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   ZSV.foreach(path, **options) {|row| block } -> nil
 *   ZSV.foreach(path, **options) -> enumerator
 *
 * Efficiently streams rows from a CSV file.
 */
static VALUE rb_zsv_foreach(int argc, VALUE *argv, VALUE klass)
{
    VALUE path, opts;
    rb_scan_args(argc, argv, "11", &path, &opts);

    RETURN_ENUMERATOR(klass, argc, argv);

    Check_Type(path, T_STRING);

    zsv_ruby_parser_t *parser = zsv_parser_new_from_path(StringValueCStr(path), opts);
    VALUE parser_obj = wrap_parser(parser);

    /* Ensure cleanup even if exception occurs */
    int state;
    rb_protect(rb_zsv_parser_each, parser_obj, &state);

    zsv_parser_close(parser);

    if (state) {
        rb_jump_tag(state);
    }

    return Qnil;
}

/*
 * call-seq:
 *   ZSV.parse(string, **options) -> array
 *
 * Parses a CSV string and returns all rows as an array.
 */
static VALUE rb_zsv_parse(int argc, VALUE *argv, VALUE klass)
{
    VALUE string, opts;
    (void)klass;
    rb_scan_args(argc, argv, "11", &string, &opts);

    Check_Type(string, T_STRING);

    zsv_ruby_parser_t *parser = zsv_parser_new_from_string(string, opts);
    VALUE result = rb_ary_new();

    VALUE row;
    while (!NIL_P(row = zsv_parser_shift(parser))) {
        rb_ary_push(result, row);
    }

    zsv_parser_free(parser);
    return result;
}

/*
 * call-seq:
 *   ZSV.read(path, **options) -> array
 *
 * Reads entire CSV file into an array of rows.
 */
static VALUE rb_zsv_read(int argc, VALUE *argv, VALUE klass)
{
    VALUE path, opts;
    (void)klass;
    rb_scan_args(argc, argv, "11", &path, &opts);

    Check_Type(path, T_STRING);

    zsv_ruby_parser_t *parser = zsv_parser_new_from_path(StringValueCStr(path), opts);
    VALUE result = rb_ary_new();

    VALUE row;
    while (!NIL_P(row = zsv_parser_shift(parser))) {
        rb_ary_push(result, row);
    }

    zsv_parser_free(parser);
    return result;
}

/*
 * call-seq:
 *   ZSV.open(path, mode="r", **options) -> parser
 *   ZSV.open(path, mode="r", **options) {|parser| block } -> result
 *
 * Opens a CSV file for reading. If a block is given, the parser is
 * automatically closed after the block completes.
 */
static VALUE rb_zsv_open(int argc, VALUE *argv, VALUE klass)
{
    VALUE path, mode, opts;
    (void)klass;
    rb_scan_args(argc, argv, "11:", &path, &mode, &opts);

    Check_Type(path, T_STRING);

    /* If mode is a hash, it's actually the options */
    if (!NIL_P(mode) && TYPE(mode) == T_HASH) {
        opts = mode;
        mode = Qnil;
    }

    /* Currently only support read mode */
    if (!NIL_P(mode) && strcmp(StringValueCStr(mode), "r") != 0) {
        rb_raise(rb_eNotImpError, "Only read mode is currently supported");
    }

    zsv_ruby_parser_t *parser = zsv_parser_new_from_path(StringValueCStr(path), opts);
    VALUE parser_obj = wrap_parser(parser);

    if (rb_block_given_p()) {
        int state;
        VALUE result = rb_protect(rb_yield, parser_obj, &state);
        zsv_parser_close(parser);

        if (state) {
            rb_jump_tag(state);
        }

        return result;
    }

    return parser_obj;
}

/* Initialize the extension */
void Init_zsv(void)
{
    /* Define module */
    mZSV = rb_define_module("ZSV");

    /* Define Parser class */
    cParser = rb_define_class_under(mZSV, "Parser", rb_cObject);
    rb_include_module(cParser, rb_mEnumerable);
    rb_define_alloc_func(cParser, zsv_parser_alloc);
    rb_define_method(cParser, "initialize", rb_zsv_parser_initialize, -1);
    rb_define_method(cParser, "shift", rb_zsv_parser_shift, 0);
    rb_define_method(cParser, "each", rb_zsv_parser_each, 0);
    rb_define_alias(cParser, "each_row", "each");
    rb_define_method(cParser, "rewind", rb_zsv_parser_rewind, 0);
    rb_define_method(cParser, "close", rb_zsv_parser_close, 0);
    rb_define_method(cParser, "headers", rb_zsv_parser_headers_get, 0);
    rb_define_method(cParser, "closed?", rb_zsv_parser_closed_p, 0);

    /* Define module methods */
    rb_define_module_function(mZSV, "foreach", rb_zsv_foreach, -1);
    rb_define_module_function(mZSV, "parse", rb_zsv_parse, -1);
    rb_define_module_function(mZSV, "read", rb_zsv_read, -1);
    rb_define_module_function(mZSV, "open", rb_zsv_open, -1);

    /* Define exceptions */
    eZSVError = rb_define_class_under(mZSV, "Error", rb_eStandardError);
    eMalformedCSVError = rb_define_class_under(mZSV, "MalformedCSVError", eZSVError);
    eInvalidEncodingError = rb_define_class_under(mZSV, "InvalidEncodingError", eZSVError);

    /* Initialize submodules */
    Init_zsv_options();
}
