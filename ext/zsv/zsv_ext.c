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

static ID id_file_p;
static ID id_read;
static ID id_to_path;
static ID id_eof_p;

static void zsv_parser_gc_mark(void *ptr)
{
    zsv_parser_mark((zsv_ruby_parser_t *)ptr);
}

static void zsv_parser_gc_compact(void *ptr)
{
    zsv_parser_compact((zsv_ruby_parser_t *)ptr);
}

static void zsv_parser_gc_free(void *ptr)
{
    zsv_parser_free((zsv_ruby_parser_t *)ptr);
}

static size_t zsv_parser_gc_memsize(const void *ptr)
{
    return zsv_parser_memsize((const zsv_ruby_parser_t *)ptr);
}

/* Not write-barrier protected: the parser stores VALUEs (row cells, headers)
 * in C memory without RB_OBJ_WRITE, so it is always rescanned by the GC. */
static const rb_data_type_t zsv_parser_type = {
    .wrap_struct_name = "ZSV::Parser",
    .function =
        {
            .dmark = zsv_parser_gc_mark,
            .dfree = zsv_parser_gc_free,
            .dsize = zsv_parser_gc_memsize,
            .dcompact = zsv_parser_gc_compact,
        },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* Unwrap the parser struct without checking that it was initialized */
static zsv_ruby_parser_t *get_parser_struct(VALUE self)
{
    zsv_ruby_parser_t *parser;
    TypedData_Get_Struct(self, zsv_ruby_parser_t, &zsv_parser_type, parser);
    return parser;
}

/* Unwrap parser from Ruby object */
static zsv_ruby_parser_t *get_parser(VALUE self)
{
    zsv_ruby_parser_t *parser = get_parser_struct(self);
    if (parser->source_kind == ZSV_SOURCE_NONE) {
        rb_raise(eZSVError, "uninitialized ZSV::Parser");
    }
    return parser;
}

/* Allocate function for Parser class: the struct is owned by the object from
 * the start, so an exception during initialize cannot leak it */
static VALUE zsv_parser_alloc(VALUE klass)
{
    zsv_ruby_parser_t *parser;
    VALUE obj = TypedData_Make_Struct(klass, zsv_ruby_parser_t, &zsv_parser_type, parser);
    zsv_parser_init_struct(parser);
    return obj;
}

/* A String with a line break is CSV data. Without one it is a path when such
 * a file exists, or when it has no comma (so "data.csv" missing still raises
 * Errno::ENOENT); otherwise it is a single CSV line such as "a,b". */
static bool zsv_string_is_csv_data(VALUE string)
{
    const char *ptr = RSTRING_PTR(string);
    long len = RSTRING_LEN(string);

    if (memchr(ptr, '\n', len) || memchr(ptr, '\r', len) || memchr(ptr, '\0', len)) {
        return true;
    }
    if (RTEST(rb_funcall(rb_cFile, id_file_p, 1, string))) {
        return false;
    }
    /* File.file? allocates: re-read the pointer, the bytes may have moved */
    return memchr(RSTRING_PTR(string), ',', len) != NULL;
}

/*
 * call-seq:
 *   ZSV::Parser.new(source, **options) -> parser
 *
 * Creates a new parser. +source+ is a path-like object (#to_path, such as a
 * Pathname), an IO-like object (anything responding to #read), a file path,
 * or CSV data. A File answers both #to_path and #read and is read as a
 * stream, from its current position; a Pathname also answers #read (the
 * whole file on every call) and is opened as a path. A String is treated as
 * CSV data when it contains a line break, or a comma and no such file
 * exists; use Parser.from_string or Parser.from_path to avoid the guess.
 */
static VALUE rb_zsv_parser_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE source, opts;
    rb_scan_args(argc, argv, "11", &source, &opts);

    zsv_ruby_parser_t *parser = get_parser_struct(self);

    if (RB_TYPE_P(source, T_STRING)) {
        if (zsv_string_is_csv_data(source)) {
            zsv_parser_init_string(parser, source, opts);
        } else {
            zsv_parser_init_path(parser, source, opts);
        }
    } else if (rb_respond_to(source, id_to_path) && !rb_respond_to(source, id_eof_p)) {
        zsv_parser_init_path(parser, source, opts);
    } else if (rb_respond_to(source, id_read)) {
        zsv_parser_init_io(parser, source, opts);
    } else {
        rb_raise(rb_eTypeError, "expected a String, path or IO-like object, got %s",
                 rb_obj_classname(source));
    }

    return self;
}

/* Allocate a parser object of +klass+; it frees itself if init raises */
static VALUE zsv_new_parser_object(VALUE klass, zsv_ruby_parser_t **parser)
{
    VALUE obj = zsv_parser_alloc(klass);
    *parser = get_parser_struct(obj);
    return obj;
}

/*
 * call-seq:
 *   ZSV::Parser.from_string(csv, **options) -> parser
 *
 * Creates a parser over CSV data held in a String (never a file path).
 */
static VALUE rb_zsv_parser_s_from_string(int argc, VALUE *argv, VALUE klass)
{
    VALUE string, opts;
    rb_scan_args(argc, argv, "11", &string, &opts);

    zsv_ruby_parser_t *parser;
    VALUE obj = zsv_new_parser_object(klass, &parser);
    zsv_parser_init_string(parser, string, opts);
    return obj;
}

/*
 * call-seq:
 *   ZSV::Parser.from_path(path, **options) -> parser
 *
 * Creates a parser over the file at +path+ (a String or Pathname).
 */
static VALUE rb_zsv_parser_s_from_path(int argc, VALUE *argv, VALUE klass)
{
    VALUE path, opts;
    rb_scan_args(argc, argv, "11", &path, &opts);

    zsv_ruby_parser_t *parser;
    VALUE obj = zsv_new_parser_object(klass, &parser);
    zsv_parser_init_path(parser, path, opts);
    return obj;
}

/*
 * call-seq:
 *   parser.shift -> array or hash or nil
 *
 * Reads and returns the next row. Returns nil at EOF.
 */
static VALUE rb_zsv_parser_shift(VALUE self)
{
    return zsv_parser_shift(get_parser(self));
}

/*
 * call-seq:
 *   parser.each {|row| block } -> parser
 *   parser.each -> enumerator
 *
 * Iterates over the remaining rows. Aliased as #each_row.
 */
static VALUE rb_zsv_parser_each(VALUE self)
{
    RETURN_ENUMERATOR(self, 0, 0);

    zsv_ruby_parser_t *parser = get_parser(self);
    VALUE row;
    while (!NIL_P(row = zsv_parser_shift(parser))) {
        rb_yield(row);
    }
    return self;
}

/*
 * call-seq:
 *   parser.rewind -> nil
 *
 * Rewinds the parser to the beginning.
 */
static VALUE rb_zsv_parser_rewind(VALUE self)
{
    zsv_parser_rewind(get_parser(self));
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
    zsv_parser_close(get_parser(self));
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
    return zsv_parser_headers(get_parser(self));
}

/*
 * call-seq:
 *   parser.closed? -> bool
 *
 * Returns true if the parser is closed.
 */
static VALUE rb_zsv_parser_closed_p(VALUE self)
{
    return zsv_parser_closed(get_parser(self)) ? Qtrue : Qfalse;
}

static VALUE zsv_read_all(VALUE parser_obj)
{
    zsv_ruby_parser_t *parser = get_parser(parser_obj);
    VALUE result = rb_ary_new();
    VALUE row;

    while (!NIL_P(row = zsv_parser_shift(parser))) {
        rb_ary_push(result, row);
    }
    return result;
}

/* rb_ensure callback: close the parser even if parsing or the block raised */
static VALUE zsv_close_parser_object(VALUE parser_obj)
{
    zsv_parser_close(get_parser(parser_obj));
    return Qnil;
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

    zsv_ruby_parser_t *parser;
    VALUE parser_obj = zsv_new_parser_object(cParser, &parser);
    zsv_parser_init_path(parser, path, opts);

    rb_ensure(rb_zsv_parser_each, parser_obj, zsv_close_parser_object, parser_obj);
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

    zsv_ruby_parser_t *parser;
    VALUE parser_obj = zsv_new_parser_object(cParser, &parser);
    zsv_parser_init_string(parser, string, opts);

    return rb_ensure(zsv_read_all, parser_obj, zsv_close_parser_object, parser_obj);
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

    zsv_ruby_parser_t *parser;
    VALUE parser_obj = zsv_new_parser_object(cParser, &parser);
    zsv_parser_init_path(parser, path, opts);

    return rb_ensure(zsv_read_all, parser_obj, zsv_close_parser_object, parser_obj);
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

    /* If mode is a hash, it's actually the options */
    if (!NIL_P(mode) && RB_TYPE_P(mode, T_HASH)) {
        opts = mode;
        mode = Qnil;
    }

    /* Currently only support read mode */
    if (!NIL_P(mode) && strcmp(StringValueCStr(mode), "r") != 0) {
        rb_raise(rb_eNotImpError, "Only read mode is currently supported");
    }

    zsv_ruby_parser_t *parser;
    VALUE parser_obj = zsv_new_parser_object(cParser, &parser);
    zsv_parser_init_path(parser, path, opts);

    if (rb_block_given_p()) {
        return rb_ensure(rb_yield, parser_obj, zsv_close_parser_object, parser_obj);
    }

    return parser_obj;
}

/* Initialize the extension */
void Init_zsv(void)
{
    /* No mutable global state: parsers are per-object and never shareable */
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

    id_file_p = rb_intern("file?");
    id_read = rb_intern("read");
    id_to_path = rb_intern("to_path");
    id_eof_p = rb_intern("eof?");

    /* Define module */
    mZSV = rb_define_module("ZSV");

    /* Define Parser class */
    cParser = rb_define_class_under(mZSV, "Parser", rb_cObject);
    rb_include_module(cParser, rb_mEnumerable);
    rb_define_alloc_func(cParser, zsv_parser_alloc);
    rb_define_singleton_method(cParser, "from_string", rb_zsv_parser_s_from_string, -1);
    rb_define_singleton_method(cParser, "from_path", rb_zsv_parser_s_from_path, -1);
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
    Init_zsv_parser();
}
