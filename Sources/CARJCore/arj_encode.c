#include "arj_core.h"
#include "arj_internal.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/*
 * ARJ encoder for methods 1...4.
 *
 * Methods 1-3 share one bitstream: LZ77 matches over a 26 KB window, emitted in
 * blocks with static Huffman tables (the scheme ARJ inherited from LHA/ar002).
 * The three methods only differ in how hard the match finder searches.
 * Method 4 uses a simpler LZ77 stream with fixed-width prefix codes and a
 * smaller (15.5 KB) window.
 *
 * The whole input is in memory, so the match finder indexes it directly
 * instead of maintaining a sliding dictionary buffer.
 */

enum {
    ENC_HASH_BITS = 15,
    ENC_HASH_SIZE = 1 << ENC_HASH_BITS,
    ENC_WINDOW_SIZE = 32768, /* power of two, >= every supported distance */
    ENC_WINDOW_MASK = ENC_WINDOW_SIZE - 1,
    ENC_BLOCK_SYMBOLS = 16384, /* block size field is 16 bits wide */
    ENC_MAX_DISTANCE_1_3 = ARJ_DICSIZ - 1,
    ENC_MAX_DISTANCE_4 = 15872, /* largest pointer method 4 can express */
    ENC_TOO_FAR = 4096
};

typedef struct enc_params {
    int max_chain;
    unsigned nice_length;
    unsigned lazy_limit; /* 0 disables lazy matching */
    size_t max_distance;
    bool drop_far_short_matches;
} enc_params;

/* ------------------------------------------------------------------------- */
/* Bit output                                                                */

typedef struct bit_writer {
    uint8_t *out;
    size_t capacity;
    size_t pos;
    uint32_t buf;
    int count;
    bool overflow;
} bit_writer;

/* Writes the low `n` bits of `value`, most significant bit first (n <= 16). */
static void bw_put(bit_writer *w, int n, unsigned value) {
    if (n <= 0) return;
    w->buf = (w->buf << n) | (value & ((1u << n) - 1u));
    w->count += n;
    while (w->count >= 8) {
        w->count -= 8;
        if (w->pos < w->capacity) {
            w->out[w->pos++] = (uint8_t)(w->buf >> w->count);
        } else {
            w->overflow = true;
        }
    }
    w->buf &= (1u << w->count) - 1u;
}

static void bw_flush(bit_writer *w) {
    if (w->count > 0) bw_put(w, 8 - w->count, 0);
}

/* ------------------------------------------------------------------------- */
/* Match finder                                                              */

typedef struct lz_state {
    const uint8_t *in;
    size_t size;
    size_t head[ENC_HASH_SIZE];   /* position + 1, 0 = empty */
    size_t prev[ENC_WINDOW_SIZE]; /* position + 1, 0 = empty */
} lz_state;

static uint32_t lz_hash(const uint8_t *p) {
    uint32_t v = (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16);
    return (v * 2654435761u) >> (32 - ENC_HASH_BITS);
}

static void lz_insert(lz_state *s, size_t pos) {
    if (pos + ARJ_THRESHOLD > s->size) return;
    uint32_t h = lz_hash(s->in + pos);
    s->prev[pos & ENC_WINDOW_MASK] = s->head[h];
    s->head[h] = pos + 1;
}

/*
 * Finds the longest match at `pos` that is strictly longer than `min_length`.
 * Must be called before `pos` itself is inserted. Returns 0 when nothing better exists.
 */
static unsigned lz_find(const lz_state *s, size_t pos, unsigned min_length, const enc_params *prm, size_t *distance) {
    size_t avail = s->size - pos;
    unsigned max_length = avail < ARJ_MAXMATCH ? (unsigned)avail : ARJ_MAXMATCH;
    unsigned best = min_length;
    size_t best_distance = 0;
    const uint8_t *cur = s->in + pos;
    int chain = prm->max_chain;

    if (max_length < ARJ_THRESHOLD || best >= max_length) return 0;

    size_t link = s->head[lz_hash(cur)];
    while (link != 0 && chain-- > 0) {
        size_t candidate = link - 1;
        size_t dist = pos - candidate;
        if (dist > prm->max_distance) break;

        const uint8_t *m = s->in + candidate;
        if (m[best] == cur[best] && m[0] == cur[0] && m[1] == cur[1]) {
            unsigned len = 0;
            while (len < max_length && m[len] == cur[len]) len++;
            if (len > best) {
                best = len;
                best_distance = dist;
                if (len >= prm->nice_length || len == max_length) break;
            }
        }
        link = s->prev[candidate & ENC_WINDOW_MASK];
    }

    if (best_distance == 0) return 0;
    if (prm->drop_far_short_matches && best == ARJ_THRESHOLD && best_distance > ENC_TOO_FAR) return 0;
    *distance = best_distance;
    return best;
}

/* ------------------------------------------------------------------------- */
/* Static Huffman coding (methods 1-3)                                       */

typedef struct huf_encoder {
    uint32_t c_freq[2 * ARJ_NC - 1];
    uint32_t p_freq[2 * ARJ_NP - 1];
    uint32_t t_freq[2 * ARJ_NT - 1];
    uint8_t c_len[ARJ_NC];
    uint16_t c_code[ARJ_NC];
    uint8_t pt_len[ARJ_NPT];
    uint16_t pt_code[ARJ_NPT];
    uint16_t left[2 * ARJ_NC - 1];
    uint16_t right[2 * ARJ_NC - 1];
    int heap[ARJ_NC + 1];
    int heapsize;
    uint16_t len_cnt[17];
    uint16_t symbols[ENC_BLOCK_SYMBOLS];
    uint16_t positions[ENC_BLOCK_SYMBOLS];
    size_t symbol_count;
} huf_encoder;

static void huf_downheap(huf_encoder *h, const uint32_t *freq, int i) {
    int j, k = h->heap[i];
    while ((j = 2 * i) <= h->heapsize) {
        if (j < h->heapsize && freq[h->heap[j]] > freq[h->heap[j + 1]]) j++;
        if (freq[k] <= freq[h->heap[j]]) break;
        h->heap[i] = h->heap[j];
        i = j;
    }
    h->heap[i] = k;
}

static void huf_count_len(huf_encoder *h, int n, int node, int depth) {
    if (node < n) {
        h->len_cnt[depth < 16 ? depth : 16]++;
    } else {
        huf_count_len(h, n, h->left[node], depth + 1);
        huf_count_len(h, n, h->right[node], depth + 1);
    }
}

/* Assigns code lengths (limited to 16 bits) to the leaves listed in `sorted` by ascending frequency. */
static void huf_make_len(huf_encoder *h, int n, int root, uint8_t *len, const uint16_t *sorted) {
    int i, k;
    uint32_t cum = 0;

    for (i = 0; i <= 16; i++) h->len_cnt[i] = 0;
    huf_count_len(h, n, root, 0);
    for (i = 16; i > 0; i--) cum += (uint32_t)h->len_cnt[i] << (16 - i);
    while (cum != (1u << 16)) {
        h->len_cnt[16]--;
        for (i = 15; i > 0; i--) {
            if (h->len_cnt[i] != 0) {
                h->len_cnt[i]--;
                h->len_cnt[i + 1] += 2;
                break;
            }
        }
        cum--;
    }
    for (i = 16; i > 0; i--) {
        k = h->len_cnt[i];
        while (--k >= 0) len[*sorted++] = (uint8_t)i;
    }
}

/* Canonical codes, matching the decoder's table construction. */
static void huf_make_code(huf_encoder *h, int n, const uint8_t *len, uint16_t *code) {
    uint16_t start[18];
    int i;
    start[0] = 0;
    start[1] = 0;
    for (i = 1; i <= 16; i++) start[i + 1] = (uint16_t)((start[i] + h->len_cnt[i]) << 1);
    for (i = 0; i < n; i++) code[i] = start[len[i]]++;
}

/* Builds a Huffman code for `freq[0..<n]`; returns the root (a leaf index < n if only one symbol is used). */
static int huf_make_tree(huf_encoder *h, int n, uint32_t *freq, uint8_t *len, uint16_t *code) {
    int i, j, k = 0, avail = n;
    uint16_t *sorted = code;

    h->heapsize = 0;
    h->heap[1] = 0;
    for (i = 0; i < n; i++) {
        len[i] = 0;
        if (freq[i]) h->heap[++h->heapsize] = i;
    }
    if (h->heapsize < 2) {
        code[h->heap[1]] = 0;
        return h->heap[1];
    }
    for (i = h->heapsize / 2; i >= 1; i--) huf_downheap(h, freq, i);

    do {
        i = h->heap[1];
        if (i < n) *sorted++ = (uint16_t)i;
        h->heap[1] = h->heap[h->heapsize--];
        huf_downheap(h, freq, 1);
        j = h->heap[1];
        if (j < n) *sorted++ = (uint16_t)j;
        k = avail++;
        freq[k] = freq[i] + freq[j];
        h->heap[1] = k;
        huf_downheap(h, freq, 1);
        h->left[k] = (uint16_t)i;
        h->right[k] = (uint16_t)j;
    } while (h->heapsize > 1);

    huf_make_len(h, n, k, len, code);
    huf_make_code(h, n, len, code);
    return k;
}

static void huf_count_t_freq(huf_encoder *h) {
    int i, k, n = ARJ_NC, count;
    for (i = 0; i < ARJ_NT; i++) h->t_freq[i] = 0;
    while (n > 0 && h->c_len[n - 1] == 0) n--;
    i = 0;
    while (i < n) {
        k = h->c_len[i++];
        if (k == 0) {
            count = 1;
            while (i < n && h->c_len[i] == 0) {
                i++;
                count++;
            }
            if (count <= 2) {
                h->t_freq[0] += (uint32_t)count;
            } else if (count <= 18) {
                h->t_freq[1]++;
            } else if (count == 19) {
                h->t_freq[0]++;
                h->t_freq[1]++;
            } else {
                h->t_freq[2]++;
            }
        } else {
            h->t_freq[k + 2]++;
        }
    }
}

static void huf_write_pt_len(huf_encoder *h, bit_writer *w, int n, int nbit, int i_special) {
    int i, k;
    while (n > 0 && h->pt_len[n - 1] == 0) n--;
    bw_put(w, nbit, (unsigned)n);
    i = 0;
    while (i < n) {
        k = h->pt_len[i++];
        if (k <= 6) {
            bw_put(w, 3, (unsigned)k);
        } else {
            bw_put(w, k - 3, (1u << (k - 3)) - 2u);
        }
        if (i == i_special) {
            while (i < 6 && h->pt_len[i] == 0) i++;
            bw_put(w, 2, (unsigned)((i - 3) & 3));
        }
    }
}

static void huf_write_c_len(huf_encoder *h, bit_writer *w) {
    int i, k, n = ARJ_NC, count;
    while (n > 0 && h->c_len[n - 1] == 0) n--;
    bw_put(w, ARJ_CBIT, (unsigned)n);
    i = 0;
    while (i < n) {
        k = h->c_len[i++];
        if (k == 0) {
            count = 1;
            while (i < n && h->c_len[i] == 0) {
                i++;
                count++;
            }
            if (count <= 2) {
                for (k = 0; k < count; k++) bw_put(w, h->pt_len[0], h->pt_code[0]);
            } else if (count <= 18) {
                bw_put(w, h->pt_len[1], h->pt_code[1]);
                bw_put(w, 4, (unsigned)(count - 3));
            } else if (count == 19) {
                bw_put(w, h->pt_len[0], h->pt_code[0]);
                bw_put(w, h->pt_len[1], h->pt_code[1]);
                bw_put(w, 4, 15);
            } else {
                bw_put(w, h->pt_len[2], h->pt_code[2]);
                bw_put(w, ARJ_CBIT, (unsigned)(count - 20));
            }
        } else {
            bw_put(w, h->pt_len[k + 2], h->pt_code[k + 2]);
        }
    }
}

static unsigned bit_length(unsigned value) {
    unsigned bits = 0;
    while (value) {
        value >>= 1;
        bits++;
    }
    return bits;
}

static void huf_encode_p(huf_encoder *h, bit_writer *w, unsigned p) {
    unsigned c = bit_length(p);
    bw_put(w, h->pt_len[c], h->pt_code[c]);
    if (c > 1) bw_put(w, (int)c - 1, p & (0xFFFFu >> (17 - c)));
}

static void huf_send_block(huf_encoder *h, bit_writer *w) {
    size_t i;
    int root = huf_make_tree(h, ARJ_NC, h->c_freq, h->c_len, h->c_code);
    bw_put(w, 16, h->c_freq[root]);

    if (root >= ARJ_NC) {
        huf_count_t_freq(h);
        root = huf_make_tree(h, ARJ_NT, h->t_freq, h->pt_len, h->pt_code);
        if (root >= ARJ_NT) {
            huf_write_pt_len(h, w, ARJ_NT, ARJ_TBIT, 3);
        } else {
            bw_put(w, ARJ_TBIT, 0);
            bw_put(w, ARJ_TBIT, (unsigned)root);
        }
        huf_write_c_len(h, w);
    } else {
        bw_put(w, ARJ_TBIT, 0);
        bw_put(w, ARJ_TBIT, 0);
        bw_put(w, ARJ_CBIT, 0);
        bw_put(w, ARJ_CBIT, (unsigned)root);
    }

    root = huf_make_tree(h, ARJ_NP, h->p_freq, h->pt_len, h->pt_code);
    if (root >= ARJ_NP) {
        huf_write_pt_len(h, w, ARJ_NP, ARJ_PBIT, -1);
    } else {
        bw_put(w, ARJ_PBIT, 0);
        bw_put(w, ARJ_PBIT, (unsigned)root);
    }

    for (i = 0; i < h->symbol_count; i++) {
        unsigned c = h->symbols[i];
        bw_put(w, h->c_len[c], h->c_code[c]);
        if (c > 255) huf_encode_p(h, w, h->positions[i]);
    }

    memset(h->c_freq, 0, sizeof(h->c_freq));
    memset(h->p_freq, 0, sizeof(h->p_freq));
    h->symbol_count = 0;
}

static void huf_output(huf_encoder *h, bit_writer *w, unsigned c, unsigned p) {
    h->symbols[h->symbol_count] = (uint16_t)c;
    h->positions[h->symbol_count] = (uint16_t)p;
    h->symbol_count++;
    h->c_freq[c]++;
    if (c > 255) h->p_freq[bit_length(p)]++;
    if (h->symbol_count == ENC_BLOCK_SYMBOLS) huf_send_block(h, w);
}

static void huf_literal(huf_encoder *h, bit_writer *w, uint8_t byte) {
    huf_output(h, w, byte, 0);
}

static void huf_match(huf_encoder *h, bit_writer *w, unsigned length, size_t distance) {
    huf_output(h, w, length + (256 - ARJ_THRESHOLD), (unsigned)(distance - 1));
}

static arj_core_status encode_method_1_3(const uint8_t *in, size_t size, const enc_params *prm, bit_writer *w) {
    lz_state *s = calloc(1, sizeof(lz_state));
    huf_encoder *h = calloc(1, sizeof(huf_encoder));
    if (s == NULL || h == NULL) {
        free(s);
        free(h);
        return ARJ_CORE_OUT_OF_MEMORY;
    }
    s->in = in;
    s->size = size;

    size_t pos = 0, prev_distance = 0;
    unsigned prev_length = 0;
    bool have_prev = false;

    while (pos < size && !w->overflow) {
        unsigned length = 0;
        size_t distance = 0;
        if (prm->lazy_limit == 0) {
            length = lz_find(s, pos, ARJ_THRESHOLD - 1, prm, &distance);
            lz_insert(s, pos);
            if (length >= ARJ_THRESHOLD) {
                huf_match(h, w, length, distance);
                for (size_t k = pos + 1; k < pos + length; k++) lz_insert(s, k);
                pos += length;
            } else {
                huf_literal(h, w, in[pos]);
                pos++;
            }
            continue;
        }

        /* Lazy evaluation: keep the previous match only if this position cannot beat it. */
        if (!have_prev || prev_length < prm->lazy_limit) {
            unsigned floor = (have_prev && prev_length > ARJ_THRESHOLD - 1) ? prev_length : ARJ_THRESHOLD - 1;
            length = lz_find(s, pos, floor, prm, &distance);
        }
        lz_insert(s, pos);

        if (have_prev && prev_length >= ARJ_THRESHOLD && length <= prev_length) {
            size_t end = pos - 1 + prev_length;
            huf_match(h, w, prev_length, prev_distance);
            for (size_t k = pos + 1; k < end; k++) lz_insert(s, k);
            pos = end;
            have_prev = false;
            prev_length = 0;
            continue;
        }
        if (have_prev) huf_literal(h, w, in[pos - 1]);
        have_prev = true;
        prev_length = length;
        prev_distance = distance;
        pos++;
    }
    if (have_prev && !w->overflow) huf_literal(h, w, in[size - 1]);
    if (h->symbol_count > 0) huf_send_block(h, w);
    bw_flush(w);

    free(s);
    free(h);
    return w->overflow ? ARJ_CORE_BUFFER_TOO_SMALL : ARJ_CORE_OK;
}

/* ------------------------------------------------------------------------- */
/* Method 4                                                                  */

/* Length code: up to 7 leading ones select the width, then `width` bits of payload. */
static void put_length_4(bit_writer *w, unsigned c) {
    unsigned width = 0, plus = 0, pwr = 1;
    while (width < 7 && c >= plus + pwr) {
        plus += pwr;
        pwr <<= 1;
        width++;
    }
    if (width > 0) bw_put(w, (int)width, (1u << width) - 1u);
    if (width < 7) bw_put(w, 1, 0);
    if (width > 0) bw_put(w, (int)width, c - plus);
}

/* Pointer code: up to 4 leading ones widen the field from 9 to 13 bits. */
static void put_pointer_4(bit_writer *w, unsigned p) {
    unsigned width = 9, plus = 0, pwr = 1u << 9;
    while (width < 13 && p >= plus + pwr) {
        plus += pwr;
        pwr <<= 1;
        width++;
    }
    if (width > 9) bw_put(w, (int)(width - 9), (1u << (width - 9)) - 1u);
    if (width < 13) bw_put(w, 1, 0);
    bw_put(w, (int)width, p - plus);
}

static arj_core_status encode_method_4(const uint8_t *in, size_t size, const enc_params *prm, bit_writer *w) {
    lz_state *s = calloc(1, sizeof(lz_state));
    if (s == NULL) return ARJ_CORE_OUT_OF_MEMORY;
    s->in = in;
    s->size = size;

    size_t pos = 0;
    while (pos < size && !w->overflow) {
        size_t distance = 0;
        unsigned length = lz_find(s, pos, ARJ_THRESHOLD - 1, prm, &distance);
        lz_insert(s, pos);
        if (length >= ARJ_THRESHOLD) {
            put_length_4(w, length - ARJ_THRESHOLD + 1);
            put_pointer_4(w, (unsigned)(distance - 1));
            for (size_t k = pos + 1; k < pos + length; k++) lz_insert(s, k);
            pos += length;
        } else {
            bw_put(w, 1, 0);
            bw_put(w, 8, in[pos]);
            pos++;
        }
    }
    bw_flush(w);

    free(s);
    return w->overflow ? ARJ_CORE_BUFFER_TOO_SMALL : ARJ_CORE_OK;
}

/* ------------------------------------------------------------------------- */

arj_core_status arj_core_encode(
    uint8_t method,
    const uint8_t *input,
    size_t input_size,
    uint8_t *output,
    size_t output_capacity,
    size_t *written_size
) {
    static const enc_params params[5] = {
        {0, 0, 0, 0, false},
        {2048, ARJ_MAXMATCH, 128, ENC_MAX_DISTANCE_1_3, true},
        {256, 128, 32, ENC_MAX_DISTANCE_1_3, true},
        {32, 32, 0, ENC_MAX_DISTANCE_1_3, true},
        {16, 32, 0, ENC_MAX_DISTANCE_4, false},
    };

    if (written_size == NULL) {
        return ARJ_CORE_BUFFER_TOO_SMALL;
    }
    *written_size = 0;

    if (method == 0) {
        if (output_capacity < input_size) return ARJ_CORE_BUFFER_TOO_SMALL;
        if (input_size > 0) memcpy(output, input, input_size);
        *written_size = input_size;
        return ARJ_CORE_OK;
    }
    if (method > 4) {
        return ARJ_CORE_UNSUPPORTED_METHOD;
    }
    if (input_size == 0) {
        return ARJ_CORE_OK;
    }

    bit_writer w;
    memset(&w, 0, sizeof(w));
    w.out = output;
    w.capacity = output_capacity;

    arj_core_status status = (method == 4)
        ? encode_method_4(input, input_size, &params[4], &w)
        : encode_method_1_3(input, input_size, &params[method], &w);
    if (status == ARJ_CORE_OK) {
        *written_size = w.pos;
    }
    return status;
}
