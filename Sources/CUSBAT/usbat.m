#import <Foundation/Foundation.h>
#import <IOUSBHost/IOUSBHost.h>
#import <IOKit/IOKitLib.h>
#import "CUSBAT.h"

static IOUSBHostInterface *gInterface = nil;
static IOUSBHostPipe *gOutPipe = nil;
static IOUSBHostPipe *gInPipe = nil;
static char gLastError[512] = {0};

static void set_error(NSString *message) {
    const char *utf8 = message.UTF8String ?: "unknown error";
    snprintf(gLastError, sizeof(gLastError), "%s", utf8);
}

static io_service_t find_interface(uint16_t vendor, uint16_t product, uint8_t number) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                     IOServiceMatching("IOUSBHostInterface"),
                                     &iterator) != KERN_SUCCESS) {
        return 0;
    }
    io_service_t result = 0;
    io_service_t service = 0;
    while ((service = IOIteratorNext(iterator)) != 0) {
        CFMutableDictionaryRef properties = NULL;
        IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0);
        NSDictionary *dictionary = (__bridge_transfer NSDictionary *)properties;
        NSNumber *vid = dictionary[@"idVendor"];
        NSNumber *pid = dictionary[@"idProduct"];
        NSNumber *index = dictionary[@"bInterfaceNumber"];
        if (vid != nil && pid != nil && index != nil &&
            vid.unsignedShortValue == vendor &&
            pid.unsignedShortValue == product &&
            index.unsignedCharValue == number) {
            result = service;
            break;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return result;
}

int32_t usbat_open(uint16_t vendor, uint16_t product, uint8_t interface_number,
                   uint8_t endpoint_out, uint8_t endpoint_in) {
    if (gInterface != nil) {
        return 0;
    }
    io_service_t service = find_interface(vendor, product, interface_number);
    if (service == 0) {
        set_error(@"AT interface not found (2c7c:0125 / interface 2)");
        return -1;
    }

    NSError *error = nil;
    IOUSBHostInterface *interface =
        [[IOUSBHostInterface alloc] initWithIOService:service
                                              options:IOUSBHostObjectInitOptionsNone
                                                queue:nil
                                                error:&error
                                      interestHandler:nil];
    if (interface == nil) {
        set_error([NSString stringWithFormat:@"cannot open AT interface: %@",
                   error.localizedDescription ?: @"unknown error"]);
        // The error code doesn't say why (it is kIOReturnInternalError when another process
        // holds the interface), but the registry does: the holder is recorded as UsbExclusiveOwner.
        CFTypeRef owner = IORegistryEntryCreateCFProperty(service, CFSTR("UsbExclusiveOwner"),
                                                          kCFAllocatorDefault, 0);
        IOObjectRelease(service);
        if (owner != NULL) {
            set_error([NSString stringWithFormat:@"AT interface held by %@", (__bridge id)owner]);
            CFRelease(owner);
            return -2;
        }
        return -4;
    }
    IOObjectRelease(service);

    IOUSBHostPipe *outPipe = [interface copyPipeWithAddress:endpoint_out error:&error];
    IOUSBHostPipe *inPipe = [interface copyPipeWithAddress:endpoint_in error:&error];
    if (outPipe == nil || inPipe == nil) {
        set_error([NSString stringWithFormat:@"cannot open AT pipes: %@",
                   error.localizedDescription ?: @"unknown error"]);
        [interface destroy];
        return -3;
    }

    gInterface = interface;
    gOutPipe = outPipe;
    gInPipe = inPipe;
    gLastError[0] = 0;
    return 0;
}

void usbat_close(void) {
    gOutPipe = nil;
    gInPipe = nil;
    if (gInterface != nil) {
        [gInterface destroy];
        gInterface = nil;
    }
}

int32_t usbat_write(const uint8_t *data, size_t length, double timeout) {
    if (gOutPipe == nil) {
        set_error(@"AT interface not open");
        return -1;
    }
    NSMutableData *buffer = [NSMutableData dataWithBytes:data length:length];
    NSUInteger transferred = 0;
    NSError *error = nil;
    BOOL ok = [gOutPipe sendIORequestWithData:buffer
                             bytesTransferred:&transferred
                            completionTimeout:timeout
                                        error:&error];
    if (!ok) {
        set_error([NSString stringWithFormat:@"AT write failed: %@",
                   error.localizedDescription ?: @"timeout"]);
        [gOutPipe abortWithError:nil];
        return -2;
    }
    return (int32_t)transferred;
}

int32_t usbat_read(uint8_t *buffer, size_t capacity, double timeout) {
    if (gInPipe == nil) {
        set_error(@"AT interface not open");
        return -1;
    }
    NSMutableData *data = [NSMutableData dataWithLength:capacity];
    NSUInteger transferred = 0;
    NSError *error = nil;
    BOOL ok = [gInPipe sendIORequestWithData:data
                            bytesTransferred:&transferred
                           completionTimeout:timeout
                                       error:&error];
    if (!ok) {
        // Abort the pending transfer so the next read starts from a clean state.
        [gInPipe abortWithError:nil];
        if (transferred > 0) {
            memcpy(buffer, data.bytes, transferred);
            return (int32_t)transferred;
        }
        // A timeout is normal while waiting for the modem. Anything else (device
        // gone, pipe stalled) is an error the caller must not mistake for "no data yet".
        if (error.code == kIOReturnTimeout) {
            return 0;
        }
        set_error([NSString stringWithFormat:@"AT read failed: %@",
                   error.localizedDescription ?: @"unknown error"]);
        return -3;
    }
    if (transferred > 0) {
        memcpy(buffer, data.bytes, transferred);
    }
    return (int32_t)transferred;
}

int32_t usbat_device_present(uint16_t vendor, uint16_t product, uint8_t interface_number) {
    io_service_t service = find_interface(vendor, product, interface_number);
    if (service == 0) {
        return 0;
    }
    IOObjectRelease(service);
    return 1;
}

void usbat_last_error(char *buffer, size_t capacity) {
    if (buffer == NULL || capacity == 0) {
        return;
    }
    snprintf(buffer, capacity, "%s", gLastError[0] ? gLastError : "");
}
