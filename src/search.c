// SIMD packed-pair kernels for goostr. Algorithm and NEON mask representation
// adapted from memchr 2.8.3, Copyright (c) 2015 Andrew Gallant (MIT).
#include <stdint.h>
#include <string.h>

typedef struct { const uint8_t *data; int64_t len; } byte_slice;
#define ALWAYS_INLINE inline __attribute__((always_inline))

#if defined(__aarch64__) && !defined(GOOSTR_SCALAR)
#include <arm_neon.h>
#define vector uint8x16_t
#define WIDTH 16
#define MASK_STEP 4
#define load(p) vld1q_u8(p)
#define splat(b) vdupq_n_u8(b)
#define equal(a,b) vceqq_u8(a,b)
#define both(a,b) vandq_u8(a,b)
#define either(a,b) vorrq_u8(a,b)
#define xorv(a,b) veorq_u8(a,b)
static inline uint64_t mask_base(vector v) {
    return vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(v), 4)), 0)
        & UINT64_C(0x8888888888888888);
}
#elif (defined(__x86_64__) || defined(_M_X64)) && !defined(GOOSTR_SCALAR)
#include <emmintrin.h>
#define vector __m128i
#define WIDTH 16
#define MASK_STEP 1
#define load(p) _mm_loadu_si128((const __m128i *)(p))
#define splat(b) _mm_set1_epi8((char)(b))
#define equal(a,b) _mm_cmpeq_epi8(a,b)
#define both(a,b) _mm_and_si128(a,b)
#define either(a,b) _mm_or_si128(a,b)
#define xorv(a,b) _mm_xor_si128(a,b)
static inline uint64_t mask_base(vector v) { return (unsigned)_mm_movemask_epi8(v); }
#endif
#define mask mask_base

// The non-prefilter path only handles needles of 2..32 bytes. Inline these
// bounded loads instead of calling memcmp: that call makes Clang spill and
// reload both predicate vectors even on iterations without a candidate.
static inline int equal_short(const uint8_t *a, const uint8_t *b, int64_t n) {
    if (n >= 16) {
        uint64_t a0, a1, a2, a3, b0, b1, b2, b3;
        memcpy(&a0, a, 8); memcpy(&b0, b, 8);
        memcpy(&a1, a + 8, 8); memcpy(&b1, b + 8, 8);
        memcpy(&a2, a + n - 16, 8); memcpy(&b2, b + n - 16, 8);
        memcpy(&a3, a + n - 8, 8); memcpy(&b3, b + n - 8, 8);
        return ((a0 ^ b0) | (a1 ^ b1) | (a2 ^ b2) | (a3 ^ b3)) == 0;
    }
    if (n >= 8) {
        uint64_t a0, a1, b0, b1;
        memcpy(&a0, a, 8); memcpy(&b0, b, 8);
        memcpy(&a1, a + n - 8, 8); memcpy(&b1, b + n - 8, 8);
        return ((a0 ^ b0) | (a1 ^ b1)) == 0;
    }
    if (n >= 4) {
        uint32_t a0, a1, b0, b1;
        memcpy(&a0, a, 4); memcpy(&b0, b, 4);
        memcpy(&a1, a + n - 4, 4); memcpy(&b1, b + n - 4, 4);
        return ((a0 ^ b0) | (a1 ^ b1)) == 0;
    }
    uint16_t a0, a1, b0, b1;
    memcpy(&a0, a, 2); memcpy(&b0, b, 2);
    memcpy(&a1, a + n - 2, 2); memcpy(&b1, b + n - 2, 2);
    return ((a0 ^ b0) | (a1 ^ b1)) == 0;
}

#define TARGET
#define PACKED packed_base
#define BYTE byte_base
#define SMALL small_base
#define SET set_base
#include "search-kernels.h"

#if (defined(__x86_64__) || defined(_M_X64)) && !defined(GOOSTR_SCALAR)
#include <immintrin.h>
#define HAVE_AVX2 1
// Compile only these functions for AVX2, never the whole translation unit.
// The compiler's cached CPU feature detection also checks OS AVX state support.
#define TARGET __attribute__((target("avx2")))
#define PACKED packed_avx2
#define BYTE byte_avx2
#define SMALL small_avx2
#define SET set_avx2
#define vector __m256i
#define WIDTH 32
#define MASK_STEP 1
#define load(p) _mm256_loadu_si256((const __m256i *)(p))
#define splat(b) _mm256_set1_epi8((char)(b))
#define equal(a,b) _mm256_cmpeq_epi8(a,b)
#define both(a,b) _mm256_and_si256(a,b)
#define either(a,b) _mm256_or_si256(a,b)
#define xorv(a,b) _mm256_xor_si256(a,b)
// Cast through uint32_t: lane 31 sets the sign bit of movemask's int result.
#define mask(v) ((uint64_t)(uint32_t)_mm256_movemask_epi8(v))
#include "search-kernels.h"
#endif

int64_t goostr_packed(byte_slice h, byte_slice n, int64_t a, int64_t b, uint8_t prefilter) {
#ifdef HAVE_AVX2
    if (h.len >= n.len && h.len - n.len >= 31 && __builtin_cpu_supports("avx2"))
        return packed_avx2(h, n, a, b, prefilter);
#endif
    return packed_base(h, n, a, b, prefilter);
}

int64_t goostr_byte(byte_slice h, uint8_t byte, uint8_t reverse) {
#ifdef HAVE_AVX2
    if (h.len >= 32 && __builtin_cpu_supports("avx2")) return byte_avx2(h, byte, reverse);
#endif
    return byte_base(h, byte, reverse);
}

int64_t goostr_byteset(byte_slice h, byte_slice n, uint8_t reverse, uint8_t invert) {
    if (h.len <= 0) return -1;
    if (n.len == 0) return invert ? (reverse ? h.len - 1 : 0) : -1;
    if (n.len <= 3) {
#ifdef HAVE_AVX2
        if (h.len >= 32 && __builtin_cpu_supports("avx2")) return set_avx2(h, n, reverse, invert);
#endif
        return set_base(h, n, reverse, invert);
    }

    // Larger sets only need membership, not ByteSet's classification and
    // SIMD shuffle tables. Building this costs one zero-fill and O(set.len).
    uint8_t members[256] = {0};
    for (int64_t i = 0; i < n.len; i++) members[n.data[i]] = 1;
    // A full set cannot have an outside byte. Only count membership when
    // the input is large enough to contain all bytes; duplicates still count once.
    if (n.len >= 256) {
        unsigned count = 0;
        for (unsigned i = 0; i < 256; i++) count += members[i];
        if (count == 256) return invert ? -1 : (reverse ? h.len - 1 : 0);
    }
    if (!reverse) {
        for (int64_t i = 0; i < h.len; i++)
            if (members[h.data[i]] != invert) return i;
    } else {
        int64_t i = h.len;
        while (i > 0) { i--; if (members[h.data[i]] != invert) return i; }
    }
    return -1;
}
