#ifndef ARJ_CORE_H
#define ARJ_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum arj_core_status {
    ARJ_CORE_OK = 0,
    ARJ_CORE_UNSUPPORTED_METHOD = 1,
    ARJ_CORE_BUFFER_TOO_SMALL = 2,
    ARJ_CORE_DECODE_ERROR = 3
} arj_core_status;

arj_core_status arj_core_decode(
    uint8_t method,
    const uint8_t *input,
    size_t input_size,
    uint8_t *output,
    size_t output_size,
    size_t *written_size
);

#ifdef __cplusplus
}
#endif

#endif
