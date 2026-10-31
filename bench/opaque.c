#include <stdint.h>
#ifdef __APPLE__
#include <pthread.h>
#include <pthread/qos.h>
#endif

typedef struct { const uint8_t *data; int64_t len; } byte_slice;

// Compiled separately, without LTO. Both runners call exactly this function.
int64_t goostr_bench_opaque(byte_slice s) { return s.len; }

// Request the same foreground scheduling class in both runners. This reduces
// Apple Silicon performance/efficiency-core variation, but does not pin a core.
int64_t goostr_bench_setup(void) {
#ifdef __APPLE__
    return pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
#else
    return 0;
#endif
}
