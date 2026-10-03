#ifndef ARJ_INTERNAL_H
#define ARJ_INTERNAL_H

/* Format constants shared by the decoder (arj_core.c) and the encoder (arj_encode.c). */
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
    ARJ_LEFT_RIGHT_SIZE = ARJ_NC * 2 + 32,
    /* Decoding stops once this many bytes past the input end were requested (corrupt sizes). */
    ARJ_MAX_OVERRUN = 64
};

#endif
