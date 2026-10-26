#include "gardens_lzma.h"
#include "LzmaEnc.h"

#include <stdlib.h>
#include <string.h>

static void *GardensSzAlloc(ISzAllocPtr p, size_t size) {
    (void)p;
    return malloc(size == 0 ? 1 : size);
}

static void GardensSzFree(ISzAllocPtr p, void *address) {
    (void)p;
    free(address);
}

static const ISzAlloc kGardensAlloc = { GardensSzAlloc, GardensSzFree };

int gardens_lzma_alone(const uint8_t *src, size_t srcLen, uint8_t **out, size_t *outLen) {
    CLzmaEncProps props;
    Byte propsEncoded[LZMA_PROPS_SIZE];
    SizeT propsSize = LZMA_PROPS_SIZE;
    SizeT destLen;
    Byte *dest;
    uint8_t *alone;
    SRes res;
    size_t i;

    if (!src || !out || !outLen || srcLen == 0) {
        return 1;
    }

    destLen = srcLen + (srcLen / 4) + 65536;
    dest = (Byte *)malloc(destLen);
    if (!dest) {
        return 2;
    }

    LzmaEncProps_Init(&props);
    props.level = 6;
    props.dictSize = 8192;
    props.lc = 3;
    props.lp = 0;
    props.pb = 2;
    props.fb = 128;
    props.writeEndMark = 0;
    props.numThreads = 1;

    res = LzmaEncode(
        dest,
        &destLen,
        src,
        srcLen,
        &props,
        propsEncoded,
        &propsSize,
        0,
        NULL,
        &kGardensAlloc,
        &kGardensAlloc
    );
    if (res != SZ_OK || propsSize != LZMA_PROPS_SIZE) {
        free(dest);
        return (int)res == 0 ? 3 : (int)res;
    }

    alone = (uint8_t *)malloc(13 + destLen);
    if (!alone) {
        free(dest);
        return 2;
    }
    memcpy(alone, propsEncoded, 5);
    for (i = 0; i < 8; i++) {
        alone[5 + i] = (uint8_t)((srcLen >> (8 * i)) & 0xFF);
    }
    memcpy(alone + 13, dest, destLen);
    free(dest);
    *out = alone;
    *outLen = 13 + destLen;
    return 0;
}
