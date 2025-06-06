//
//  hooks.m
//  simulator-trainer
//
//  Created by m1book on 6/3/25.
//

#import <Foundation/Foundation.h>
#import <os/log.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "dyld-interposing.h"


/*
extern CFTypeRef CFPreferencesCopyAppValue(CFStringRef key, CFStringRef applicationID);
CFTypeRef new_CFPreferencesCopyAppValue(CFStringRef key, CFStringRef applicationID) {
    return CFPreferencesCopyAppValue(key, applicationID);
}
DYLD_INTERPOSE(new_CFPreferencesCopyAppValue, CFPreferencesCopyAppValue)
*/

extern BOOL os_log_type_enabled(os_log_t oslog, os_log_type_t type);
BOOL new_os_log_type_enabled(os_log_t oslog, os_log_type_t type) {
    return YES;
}
DYLD_INTERPOSE(new_os_log_type_enabled, os_log_type_enabled)


extern BOOL os_variant_has_internal_ui(const char *variant);
BOOL new_os_variant_has_internal_ui(const char *variant) {
    return YES;
}
DYLD_INTERPOSE(new_os_variant_has_internal_ui, os_variant_has_internal_ui)
