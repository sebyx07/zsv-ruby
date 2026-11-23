/* Common header for zsv Ruby extension */
#ifndef ZSV_RUBY_COMMON_H
#define ZSV_RUBY_COMMON_H

#include <ruby.h>
#include <ruby/encoding.h>
#include <stdbool.h>
#include <zsv.h>

/* Module and class references */
extern VALUE mZSV;
extern VALUE cParser;
extern VALUE eZSVError;
extern VALUE eMalformedCSVError;
extern VALUE eInvalidEncodingError;

/* Memory management macros - use Ruby's built-in */
#define ZSV_ALLOC(type) RB_ALLOC(type)
#define ZSV_ALLOC_N(type, n) RB_ALLOC_N(type, n)
#define ZSV_REALLOC_N(var, type, n) RB_REALLOC_N(var, type, n)

#endif /* ZSV_RUBY_COMMON_H */
