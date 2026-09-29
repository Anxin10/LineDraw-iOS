#ifndef LINEDRAW_DEVICE_BRIDGE_H
#define LINEDRAW_DEVICE_BRIDGE_H
#include <stddef.h>
int ld_validate_pairing(const unsigned char *bytes, size_t len);
#include <stdint.h>
// Returned UTF-8 JSON strings are owned by caller. Free with ld_string_free.
// No long-lived credential in JSON responses. Pairing status contains a temporary PIN.
// Only one pairing or device session at a time.
char *ld_start(const uint8_t *pairing, size_t length, const char *configuration);
char *ld_status(void);
void ld_stop(void);
// Explicit, finite on-phone pairing; configuration contains only own IPv4 addresses.
char *ld_pair_start(const char *configuration);
char *ld_pair_status(void);
void ld_pair_stop(void);
// Returns required size without consuming if buffer is NULL/too small.
// Successful copy consumes the secret; caller must immediately save to Keychain.
size_t ld_pair_take_record(uint8_t *buffer, size_t capacity);
void ld_string_free(char *value);
#endif
