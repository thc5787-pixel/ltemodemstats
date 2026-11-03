#ifndef CUSBAT_H
#define CUSBAT_H

#include <stddef.h>
#include <stdint.h>

/// Opens the vendor-specific USB interface of the QDC507/EC25 modem.
/// Returns 0 on success; -1 device not found, -2 interface held exclusively by
/// another process, -3 pipes unavailable, -4 other open failure.
int32_t usbat_open(uint16_t vendor, uint16_t product, uint8_t interface_number,
                   uint8_t endpoint_out, uint8_t endpoint_in);

/// Releases the interface and pipes.
void usbat_close(void);

/// Writes a buffer to the bulk OUT pipe. Returns bytes written or a negative value.
int32_t usbat_write(const uint8_t *data, size_t length, double timeout);

/// Reads from the bulk IN pipe.
/// Returns bytes read, 0 on timeout (nothing available), negative on a transfer error.
int32_t usbat_read(uint8_t *buffer, size_t capacity, double timeout);

/// 1 when the modem's AT interface is present on the USB bus.
int32_t usbat_device_present(uint16_t vendor, uint16_t product, uint8_t interface_number);

/// Copies the last error message into buffer (NUL terminated).
void usbat_last_error(char *buffer, size_t capacity);

#endif /* CUSBAT_H */
