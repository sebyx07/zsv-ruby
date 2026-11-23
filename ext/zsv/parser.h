/* Parser wrapper around zsv */
#ifndef ZSV_RUBY_PARSER_H
#define ZSV_RUBY_PARSER_H

#include "common.h"
#include "options.h"
#include "row.h"

/* Where the parser reads its input from */
typedef enum {
    ZSV_SOURCE_NONE = 0, /* not initialized yet */
    ZSV_SOURCE_FILE,     /* FILE* opened from a path */
    ZSV_SOURCE_STRING,   /* frozen Ruby String held in `source` */
    ZSV_SOURCE_IO,       /* Ruby object responding to #read held in `source` */
} zsv_source_kind_t;

/* Parser state, owned by a ZSV::Parser TypedData object. Every VALUE here is
 * marked by zsv_parser_mark(); the struct is freed by zsv_parser_free(). */
typedef struct {
    zsv_parser zsv;                 /* zsv parser instance */
    zsv_source_kind_t source_kind;  /* Input kind */
    FILE *file;                     /* File handle (ZSV_SOURCE_FILE) */
    VALUE source;                   /* String or IO object (pinned: zsv reads from it) */
    size_t source_offset;           /* Read position in a String source */
    zsv_ruby_options_t options;     /* Parser options */
    zsv_row_builder_t *row_builder; /* Row builder */
    VALUE row_buffer;               /* Buffer of parsed rows (Ruby array) */
    VALUE headers;                  /* Parsed headers (if header mode) */
    size_t record_count;            /* Records zsv has emitted: the 1-based line in errors */
    size_t lines_skipped;           /* Number of lines skipped */
    bool header_row_processed;      /* Whether header row was processed */
    bool closed;                    /* Whether parser is closed */
    bool eof_reached;               /* Whether EOF (and zsv_finish) was reached */
    bool parsing;                   /* True while inside zsv (reentrancy guard) */
    bool column_overflow;           /* zsv reported a row wider than max_columns */
    bool row_truncated;             /* zsv reported a row that did not fit in its buffer */
    int exception_state;            /* rb_protect state of an exception raised in a callback */
} zsv_ruby_parser_t;

/* Initialize symbols (called from Init_zsv) */
void Init_zsv_parser(void);

/* Reset a freshly allocated struct to the uninitialized state */
void zsv_parser_init_struct(zsv_ruby_parser_t *parser);

/* Initialize an allocated parser from a file path, String or IO object.
 * May raise; the parser is then left for zsv_parser_free() to clean up. */
void zsv_parser_init_path(zsv_ruby_parser_t *parser, VALUE path, VALUE opts_hash);
void zsv_parser_init_string(zsv_ruby_parser_t *parser, VALUE string, VALUE opts_hash);
void zsv_parser_init_io(zsv_ruby_parser_t *parser, VALUE io, VALUE opts_hash);

/* GC support */
void zsv_parser_mark(zsv_ruby_parser_t *parser);
void zsv_parser_compact(zsv_ruby_parser_t *parser);
size_t zsv_parser_memsize(const zsv_ruby_parser_t *parser);

/* Free parser and associated resources */
void zsv_parser_free(zsv_ruby_parser_t *parser);

/* Parse next row, returns Ruby array or hash, or nil at EOF */
VALUE zsv_parser_shift(zsv_ruby_parser_t *parser);

/* Rewind parser to beginning */
void zsv_parser_rewind(zsv_ruby_parser_t *parser);

/* Close parser */
void zsv_parser_close(zsv_ruby_parser_t *parser);

/* Get headers */
VALUE zsv_parser_headers(zsv_ruby_parser_t *parser);

/* Check if parser is closed */
bool zsv_parser_closed(zsv_ruby_parser_t *parser);

#endif /* ZSV_RUBY_PARSER_H */
