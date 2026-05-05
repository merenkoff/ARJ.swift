#include "arj_core.h"

#include <stdbool.h>
#include <string.h>

enum {
    ARJ_CODE_BIT = 16,
    ARJ_THRESHOLD = 3,
    ARJ_DICSIZ = 26624,
    ARJ_FDICSIZ = 32768,
    ARJ_MAXMATCH = 256,
    ARJ_NC = 255 + ARJ_MAXMATCH + 2 - ARJ_THRESHOLD,
    ARJ_NP = 17,
    ARJ_CBIT = 9,
    ARJ_NT = ARJ_CODE_BIT + 3,
    ARJ_PBIT = 5,
    ARJ_TBIT = 5,
    ARJ_NPT = (ARJ_NT > ARJ_NP ? ARJ_NT : ARJ_NP),
    ARJ_CTABLESIZE = 4096,
    ARJ_PTABLESIZE = 256,
    ARJ_LEFT_RIGHT_SIZE = ARJ_NC * 2 + 32
};

typedef struct arj_decoder {
    const uint8_t *input;
    size_t input_size;
    size_t input_pos;
    uint8_t *output;
    size_t output_size;
    size_t output_pos;

    uint16_t bitbuf;
    uint8_t byte_buf;
    int bitcount;
    int16_t blocksize;

    uint16_t c_table[ARJ_CTABLESIZE];
    uint16_t pt_table[ARJ_PTABLESIZE];
    uint16_t left[ARJ_LEFT_RIGHT_SIZE];
    uint16_t right[ARJ_LEFT_RIGHT_SIZE];
    uint8_t c_len[ARJ_NC];
    uint8_t pt_len[ARJ_NPT];
} arj_decoder;

static bool arj_fillbuf(arj_decoder *d, int n) {
    while (d->bitcount < n) {
        d->bitbuf = (uint16_t)((d->bitbuf << d->bitcount) | ((unsigned int)d->byte_buf >> (8 - d->bitcount)));
        n -= d->bitcount;
        if (d->input_pos < d->input_size) {
            d->byte_buf = d->input[d->input_pos++];
        } else {
            d->byte_buf = 0;
        }
        d->bitcount = 8;
    }
    d->bitcount -= n;
    d->bitbuf = (uint16_t)((d->bitbuf << n) | (d->byte_buf >> (8 - n)));
    d->byte_buf = (uint8_t)(d->byte_buf << n);
    return true;
}

static int arj_getbits(arj_decoder *d, int n) {
    int rc = d->bitbuf >> (ARJ_CODE_BIT - n);
    arj_fillbuf(d, n);
    return rc;
}

static bool arj_make_table(
    arj_decoder *d,
    int nchar,
    uint8_t *bitlen,
    int tablebits,
    uint16_t *table,
    int tablesize
) {
    uint16_t count[17] = {0};
    uint16_t weight[17] = {0};
    uint16_t start[18] = {0};
    uint16_t *p;
    unsigned int i, k, len, ch, jutbits, avail, nextcode, mask;

    for (i = 0; i < (unsigned int)nchar; i++) {
        if (bitlen[i] > 16) {
            return false;
        }
        count[bitlen[i]]++;
    }
    start[1] = 0;
    for (i = 1; i <= 16; i++) {
        start[i + 1] = (uint16_t)(start[i] + (count[i] << (16 - i)));
    }
    if (start[17] != (uint16_t)(1 << 16)) {
        return false;
    }

    jutbits = 16 - tablebits;
    for (i = 1; (int)i <= tablebits; i++) {
        start[i] >>= jutbits;
        weight[i] = (uint16_t)(1 << (tablebits - i));
    }
    while (i <= 16) {
        weight[i] = (uint16_t)(1 << (16 - i));
        i++;
    }

    i = start[tablebits + 1] >> jutbits;
    if (i != (uint16_t)(1 << 16)) {
        k = 1U << tablebits;
        while (i != k) {
            if ((int)i >= tablesize) return false;
            table[i++] = 0;
        }
    }

    avail = nchar;
    mask = 1U << (15 - tablebits);
    for (ch = 0; (int)ch < nchar; ch++) {
        if ((len = bitlen[ch]) == 0) continue;
        k = start[len];
        nextcode = (uint16_t)(k + weight[len]);
        if ((int)len <= tablebits) {
            if (nextcode > (unsigned int)tablesize) return false;
            for (i = start[len]; i < nextcode; i++) {
                table[i] = (uint16_t)ch;
            }
        } else {
            p = &table[k >> jutbits];
            i = len - tablebits;
            while (i != 0) {
                if (*p == 0) {
                    if (avail >= ARJ_LEFT_RIGHT_SIZE) return false;
                    d->right[avail] = d->left[avail] = 0;
                    *p = (uint16_t)avail;
                    avail++;
                }
                p = (k & mask) ? &d->right[*p] : &d->left[*p];
                k <<= 1;
                i--;
            }
            *p = (uint16_t)ch;
        }
        start[len] = (uint16_t)nextcode;
    }
    return true;
}

static bool arj_read_pt_len(arj_decoder *d, int nn, int nbit, int i_special) {
    int i, n;
    int16_t c;
    uint16_t mask;

    n = arj_getbits(d, nbit);
    if (n == 0) {
        c = (short)arj_getbits(d, nbit);
        for (i = 0; i < nn; i++) d->pt_len[i] = 0;
        for (i = 0; i < ARJ_PTABLESIZE; i++) d->pt_table[i] = (uint16_t)c;
        return true;
    }

    i = 0;
    if (n >= ARJ_NPT) n = ARJ_NPT;
    while (i < n) {
        c = d->bitbuf >> 13;
        if (c == 7) {
            mask = 1 << 12;
            while (mask & d->bitbuf) {
                mask >>= 1;
                c++;
            }
        }
        arj_fillbuf(d, (c < 7) ? 3 : (int)(c - 3));
        d->pt_len[i++] = (uint8_t)c;
        if (i == i_special) {
            c = arj_getbits(d, 2);
            while (--c >= 0 && i < nn) d->pt_len[i++] = 0;
        }
    }
    while (i < nn) d->pt_len[i++] = 0;
    return arj_make_table(d, nn, d->pt_len, 8, d->pt_table, ARJ_PTABLESIZE);
}

static bool arj_read_c_len(arj_decoder *d) {
    int16_t i, c, n;
    uint16_t mask;

    n = arj_getbits(d, ARJ_CBIT);
    if (n == 0) {
        c = arj_getbits(d, ARJ_CBIT);
        for (i = 0; i < ARJ_NC; i++) d->c_len[i] = 0;
        for (i = 0; i < ARJ_CTABLESIZE; i++) d->c_table[i] = (uint16_t)c;
        return true;
    }

    i = 0;
    while (i < n) {
        c = d->pt_table[d->bitbuf >> 8];
        if (c >= ARJ_NT) {
            mask = 1 << 7;
            do {
                c = (d->bitbuf & mask) ? d->right[c] : d->left[c];
                mask >>= 1;
            } while (c >= ARJ_NT);
        }
        arj_fillbuf(d, d->pt_len[c]);
        if (c <= 2) {
            if (c == 0) c = 1;
            else if (c == 1) c = (int16_t)(arj_getbits(d, 4) + 3);
            else c = (int16_t)(arj_getbits(d, ARJ_CBIT) + 20);
            while (--c >= 0 && i < ARJ_NC) d->c_len[i++] = 0;
        } else {
            d->c_len[i++] = (uint8_t)(c - 2);
        }
    }
    while (i < ARJ_NC) d->c_len[i++] = 0;
    return arj_make_table(d, ARJ_NC, d->c_len, 12, d->c_table, ARJ_CTABLESIZE);
}

static bool arj_decode_c(arj_decoder *d, uint16_t *out) {
    uint16_t j, mask;
    if (d->blocksize == 0) {
        d->blocksize = (int16_t)arj_getbits(d, ARJ_CODE_BIT);
        if (!arj_read_pt_len(d, ARJ_NT, ARJ_TBIT, 3)) return false;
        if (!arj_read_c_len(d)) return false;
        if (!arj_read_pt_len(d, ARJ_NP, ARJ_PBIT, -1)) return false;
    }
    d->blocksize--;
    j = d->c_table[d->bitbuf >> 4];
    if (j >= ARJ_NC) {
        mask = 1 << 3;
        do {
            j = (d->bitbuf & mask) ? d->right[j] : d->left[j];
            mask >>= 1;
        } while (j >= ARJ_NC);
    }
    arj_fillbuf(d, d->c_len[j]);
    *out = j;
    return true;
}

static uint16_t arj_decode_p(arj_decoder *d) {
    uint16_t j, mask;
    j = d->pt_table[d->bitbuf >> 8];
    if (j >= ARJ_NP) {
        mask = 1 << 7;
        do {
            j = (d->bitbuf & mask) ? d->right[j] : d->left[j];
            mask >>= 1;
        } while (j >= ARJ_NP);
    }
    arj_fillbuf(d, d->pt_len[j]);
    if (j != 0) {
        j--;
        j = (uint16_t)((1U << j) + arj_getbits(d, j));
    }
    return j;
}

static bool arj_decode_method_1_3(arj_decoder *d, size_t origsize) {
    int16_t i, r, c;
    static int16_t j;
    uint8_t dec_text[ARJ_DICSIZ];
    size_t count = origsize;

    d->blocksize = 0;
    d->bitbuf = 0;
    d->byte_buf = 0;
    d->bitcount = 0;
    arj_fillbuf(d, 16);

    r = 0;
    while (count > 0) {
        uint16_t cv;
        if (!arj_decode_c(d, &cv)) return false;
        c = (int16_t)cv;
        if (c <= 255) {
            if (d->output_pos >= d->output_size) return false;
            dec_text[r] = (uint8_t)c;
            d->output[d->output_pos++] = dec_text[r];
            count--;
            if (++r >= ARJ_DICSIZ) r = 0;
        } else {
            j = (int16_t)(c - (255 + 1 - ARJ_THRESHOLD));
            if ((size_t)j > count) return false;
            count -= (size_t)j;
            i = (int16_t)(r - (int16_t)arj_decode_p(d) - 1);
            if (i < 0) i += ARJ_DICSIZ;
            while (--j >= 0) {
                if (d->output_pos >= d->output_size) return false;
                dec_text[r] = dec_text[i];
                d->output[d->output_pos++] = dec_text[r];
                if (++r >= ARJ_DICSIZ) r = 0;
                if (++i >= ARJ_DICSIZ) i = 0;
            }
        }
    }
    return true;
}

static int16_t arj_decode_ptr(arj_decoder *d) {
    int16_t c, width, plus, pwr;
    plus = 0;
    pwr = 1 << 9;
    for (width = 9; width < 13; width++) {
        c = (int16_t)arj_getbits(d, 1);
        if (c == 0) break;
        plus += pwr;
        pwr <<= 1;
    }
    if (width != 0) c = (int16_t)arj_getbits(d, width);
    c += plus;
    return c;
}

static int16_t arj_decode_len(arj_decoder *d) {
    int16_t c, width, plus, pwr;
    plus = 0;
    pwr = 1;
    for (width = 0; width < 7; width++) {
        c = (int16_t)arj_getbits(d, 1);
        if (c == 0) break;
        plus += pwr;
        pwr <<= 1;
    }
    if (width != 0) c = (int16_t)arj_getbits(d, width);
    c += plus;
    return c;
}

static bool arj_decode_method_4(arj_decoder *d, size_t origsize) {
    int i, j, c, r;
    unsigned long ncount = 0;
    uint8_t ntext[ARJ_FDICSIZ];

    d->bitbuf = 0;
    d->byte_buf = 0;
    d->bitcount = 0;
    arj_fillbuf(d, 16);

    r = 0;
    while (ncount < origsize) {
        c = arj_decode_len(d);
        if (c == 0) {
            if (d->output_pos >= d->output_size) return false;
            ncount++;
            ntext[r] = (uint8_t)(d->bitbuf >> 8);
            arj_fillbuf(d, 8);
            d->output[d->output_pos++] = ntext[r];
            if (++r >= ARJ_FDICSIZ) r = 0;
        } else {
            j = c - 1 + ARJ_THRESHOLD;
            if ((unsigned long)j > (unsigned long)(origsize - ncount)) return false;
            ncount += (unsigned long)j;
            i = r - arj_decode_ptr(d) - 1;
            if (i < 0) i += ARJ_FDICSIZ;
            while (j-- > 0) {
                if (d->output_pos >= d->output_size) return false;
                ntext[r] = ntext[i];
                d->output[d->output_pos++] = ntext[r];
                if (++r >= ARJ_FDICSIZ) r = 0;
                if (++i >= ARJ_FDICSIZ) i = 0;
            }
        }
    }
    return true;
}

arj_core_status arj_core_decode(
    uint8_t method,
    const uint8_t *input,
    size_t input_size,
    uint8_t *output,
    size_t output_size,
    size_t *written_size
) {
    if (written_size == NULL) {
        return ARJ_CORE_BUFFER_TOO_SMALL;
    }
    *written_size = 0;

    if (output_size == 0 && input_size != 0) {
        return ARJ_CORE_BUFFER_TOO_SMALL;
    }

    if (method == 0) {
        if (output_size < input_size) return ARJ_CORE_BUFFER_TOO_SMALL;
        if (input_size > 0) memcpy(output, input, input_size);
        *written_size = input_size;
        return ARJ_CORE_OK;
    }

    arj_decoder d;
    memset(&d, 0, sizeof(d));
    d.input = input;
    d.input_size = input_size;
    d.output = output;
    d.output_size = output_size;

    bool ok = false;
    switch (method) {
        case 1:
        case 2:
        case 3:
            ok = arj_decode_method_1_3(&d, output_size);
            break;
        case 4:
            ok = arj_decode_method_4(&d, output_size);
            break;
        default:
            return ARJ_CORE_UNSUPPORTED_METHOD;
    }

    if (!ok) {
        return ARJ_CORE_DECODE_ERROR;
    }
    *written_size = d.output_pos;
    return ARJ_CORE_OK;
}
