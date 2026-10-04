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
    ARJ_CORE_DECODE_ERROR = 3,
    ARJ_CORE_OUT_OF_MEMORY = 4
} arj_core_status;

/*
 * Decodes `input` (compressed with `method` 0...4) into exactly `output_size` bytes.
 * Thread-safe: all decoder state lives on the stack.
 */
arj_core_status arj_core_decode(
    uint8_t method,
    const uint8_t *input,
    size_t input_size,
    uint8_t *output,
    size_t output_size,
    size_t *written_size
);

/*
 * Compresses `input` with `method` 0...4 into `output`.
 * Returns ARJ_CORE_BUFFER_TOO_SMALL as soon as the result would exceed
 * `output_capacity`; callers typically pass the input size and fall back
 * to storing the data uncompressed in that case.
 */
arj_core_status arj_core_encode(
    uint8_t method,
    const uint8_t *input,
    size_t input_size,
    uint8_t *output,
    size_t output_capacity,
    size_t *written_size
);

#ifdef __cplusplus
}
#endif

#endif
