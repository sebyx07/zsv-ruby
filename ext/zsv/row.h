/* Row handling and conversion */
#ifndef ZSV_RUBY_ROW_H
#define ZSV_RUBY_ROW_H

#include "common.h"

/* Row builder for efficient conversion from zsv cells to Ruby arrays/hashes.
 * Every VALUE held here is reachable only through the C struct, so the owning
 * parser must call zsv_row_builder_mark() and zsv_row_builder_compact(). */
typedef struct {
    VALUE *cells;               /* Ruby string cells of the current row */
    size_t count;               /* Number of cells in current row */
    size_t capacity;            /* Allocated capacity */
    VALUE headers;              /* Private frozen copy of the headers (hash mode) */
    bool has_duplicate_headers; /* First occurrence wins, as in CSV::Row#to_h */
    rb_encoding *encoding;      /* String encoding */
} zsv_row_builder_t;

/* Initialize row builder */
zsv_row_builder_t *zsv_row_builder_new(rb_encoding *encoding);

/* Free row builder */
void zsv_row_builder_free(zsv_row_builder_t *builder);

/* GC support */
void zsv_row_builder_mark(zsv_row_builder_t *builder);
void zsv_row_builder_compact(zsv_row_builder_t *builder);
size_t zsv_row_builder_memsize(const zsv_row_builder_t *builder);

/* Reset row builder for next row */
void zsv_row_builder_reset(zsv_row_builder_t *builder);

/* Add cell to current row */
void zsv_row_builder_add_cell(zsv_row_builder_t *builder, const unsigned char *data, size_t length);

/* Build Ruby array from current row */
VALUE zsv_row_builder_to_array(zsv_row_builder_t *builder);

/* Build Ruby hash from current row (requires headers) */
VALUE zsv_row_builder_to_hash(zsv_row_builder_t *builder);

/* Set headers for hash mode (Qnil clears them) */
void zsv_row_builder_set_headers(zsv_row_builder_t *builder, VALUE headers);

#endif /* ZSV_RUBY_ROW_H */
