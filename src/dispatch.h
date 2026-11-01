#ifndef GOOSTR_DISPATCH_H
#define GOOSTR_DISPATCH_H

#include <stdint.h>

// Expose Goose's compile-time setting, not a per-call CPU feature check.
// C compilers fold this away, including all dispatch setup when disabled.
static inline uint8_t goostr_runtime_simd(void) { return GS_SIMD != 0; }

#endif
