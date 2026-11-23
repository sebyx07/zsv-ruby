/* Row handling and conversion implementation */
#include "row.h"

#define INITIAL_ROW_CAPACITY 32

zsv_row_builder_t *zsv_row_builder_new(rb_encoding *encoding)
{
    zsv_row_builder_t *builder = ZSV_ALLOC(zsv_row_builder_t);

    builder->capacity = INITIAL_ROW_CAPACITY;
    builder->cells = ZSV_ALLOC_N(VALUE, builder->capacity);
    builder->count = 0;
    builder->headers = Qnil;
    builder->has_duplicate_headers = false;
    builder->encoding = encoding;

    return builder;
}

void zsv_row_builder_free(zsv_row_builder_t *builder)
{
    if (builder) {
        xfree(builder->cells);
        xfree(builder);
    }
}

void zsv_row_builder_mark(zsv_row_builder_t *builder)
{
    rb_gc_mark_movable(builder->headers);
    for (size_t i = 0; i < builder->count; i++) {
        rb_gc_mark_movable(builder->cells[i]);
    }
}

void zsv_row_builder_compact(zsv_row_builder_t *builder)
{
    builder->headers = rb_gc_location(builder->headers);
    for (size_t i = 0; i < builder->count; i++) {
        builder->cells[i] = rb_gc_location(builder->cells[i]);
    }
}

size_t zsv_row_builder_memsize(const zsv_row_builder_t *builder)
{
    return sizeof(*builder) + builder->capacity * sizeof(VALUE);
}

void zsv_row_builder_reset(zsv_row_builder_t *builder)
{
    builder->count = 0;
}

static void zsv_row_builder_ensure_capacity(zsv_row_builder_t *builder, size_t needed)
{
    if (needed <= builder->capacity) {
        return;
    }

    /* Double capacity until we have enough */
    size_t new_capacity = builder->capacity;
    while (new_capacity < needed) {
        new_capacity *= 2;
    }

    ZSV_REALLOC_N(builder->cells, VALUE, new_capacity);
    builder->capacity = new_capacity;
}

void zsv_row_builder_add_cell(zsv_row_builder_t *builder, const unsigned char *data, size_t length)
{
    zsv_row_builder_ensure_capacity(builder, builder->count + 1);

    /* Create Ruby string with proper encoding. The allocation may run GC,
     * which is why the cells collected so far are marked by the parser. */
    VALUE str = rb_enc_str_new((const char *)data, length, builder->encoding);

    /* Freeze string for memory efficiency (shared strings) */
    rb_str_freeze(str);

    builder->cells[builder->count++] = str;
}

VALUE zsv_row_builder_to_array(zsv_row_builder_t *builder)
{
    return rb_ary_new_from_values(builder->count, builder->cells);
}

VALUE zsv_row_builder_to_hash(zsv_row_builder_t *builder)
{
    if (NIL_P(builder->headers)) {
        rb_raise(rb_eRuntimeError, "Headers not set for hash conversion");
    }

    /* RARRAY_AREF, not a cached RARRAY_CONST_PTR: rb_hash_aset can trigger
     * GC with auto-compaction, which may move an embedded array's storage */
    VALUE headers = builder->headers;
    size_t header_count = RARRAY_LEN(builder->headers);
    size_t cell_count = builder->count;

    /* Pre-allocate hash with expected size (Ruby 3.2+) */
#ifdef HAVE_RB_HASH_NEW_CAPA
    VALUE hash = rb_hash_new_capa(header_count > cell_count ? header_count : cell_count);
#else
    VALUE hash = rb_hash_new();
#endif

    /* Like CSV, every header is a key; missing trailing fields are nil */
    for (size_t i = 0; i < header_count; i++) {
        VALUE header = RARRAY_AREF(headers, i);
        if (builder->has_duplicate_headers && rb_hash_lookup2(hash, header, Qundef) != Qundef) {
            continue;
        }
        rb_hash_aset(hash, header, i < cell_count ? builder->cells[i] : Qnil);
    }

    /* Rare case: more cells than headers, add with numeric keys */
    for (size_t i = header_count; i < cell_count; i++) {
        rb_hash_aset(hash, SIZET2NUM(i), builder->cells[i]);
    }

    return hash;
}

/* Header strings are copied and frozen so that the caller mutating its
 * header array (or the strings in it) cannot change the keys mid-parse, and
 * so rb_hash_aset does not have to dup an unfrozen String key on every row. */
static VALUE zsv_row_builder_freeze_headers(VALUE headers)
{
    long count = RARRAY_LEN(headers);
    VALUE copy = rb_ary_new_capa(count);

    for (long i = 0; i < count; i++) {
        VALUE header = RARRAY_AREF(headers, i);
        rb_ary_push(copy, RB_TYPE_P(header, T_STRING) ? rb_str_new_frozen(header) : header);
    }

    return rb_ary_freeze(copy);
}

static bool zsv_row_builder_has_duplicates(VALUE headers)
{
    long count = RARRAY_LEN(headers);
    VALUE seen = rb_hash_new();

    for (long i = 0; i < count; i++) {
        VALUE header = RARRAY_AREF(headers, i);
        if (rb_hash_lookup2(seen, header, Qundef) != Qundef) {
            return true;
        }
        rb_hash_aset(seen, header, Qtrue);
    }

    return false;
}

void zsv_row_builder_set_headers(zsv_row_builder_t *builder, VALUE headers)
{
    if (NIL_P(headers)) {
        builder->headers = Qnil;
        builder->has_duplicate_headers = false;
        return;
    }

    Check_Type(headers, T_ARRAY);
    VALUE frozen = zsv_row_builder_freeze_headers(headers);
    builder->has_duplicate_headers = zsv_row_builder_has_duplicates(frozen);
    builder->headers = frozen;
}
