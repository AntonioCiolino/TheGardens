#pragma once
#include <stddef.h>
#include <stdint.h>

/* LZMA1 "alone" stream: 13-byte header (props 0x5D, dict 8192, exact size) and no end marker.
   Caller frees *out with free(). Returns 0 on success. */
int gardens_lzma_alone(const uint8_t *src, size_t srcLen, uint8_t **out, size_t *outLen);
