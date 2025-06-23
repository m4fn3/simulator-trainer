//
//  ObjseeTraceLauncher.m
//  simulator-trainer
//
//  Created by m1book on 6/21/25.
//

#import "TerminalWindowController.h"
#import "ObjseeTraceLauncher.h"
#import "AppBinaryPatcher.h"

typedef enum {
    TRACER_ARG_FORMAT_NONE,
    TRACER_ARG_FORMAT_BASIC,
    TRACER_ARG_FORMAT_CLASS,
    TRACER_ARG_FORMAT_DESCRIPTIVE,
    TRACER_ARG_FORMAT_DESCRIPTIVE_COMPACT,
} tracer_argument_format_t;

typedef struct {
    bool include_formatted_trace;
    bool include_event_json;
    bool output_as_json;
    bool include_colors;
    bool include_thread_id;
    tracer_argument_format_t args;
    bool include_indents;
    bool include_indent_separators;
    bool variable_separator_spacing;
    uint32_t static_separator_spacing;
    const char *indent_char;
    const char *indent_separator_char;
    bool include_newline_in_formatted_trace;
} tracer_format_options_t;

typedef enum {
    TRACER_TRANSPORT_SOCKET,
    TRACER_TRANSPORT_FILE,
    TRACER_TRANSPORT_STDOUT,
    TRACER_TRANSPORT_CUSTOM,
} tracer_transport_type_t;

typedef struct {
    const char *type_encoding;
    const char *objc_class_name;
    const char *block_signature;
    const char *description;
    Class objc_class;
    void *address;
    size_t size;
} tracer_argument_t;

typedef struct {
    const char *host;
    uint32_t port;
    const char *file_path;
    void *custom_context;
} tracer_transport_config_t;

typedef struct tracer_event_t {
    const char *formatted_output;
    const char *class_name;
    const char *method_name;
    bool is_class_method;
    const char *image_path;
    uint16_t thread_id;
    uint32_t trace_depth;
    uint32_t real_depth;
    const char *method_signature;
    tracer_argument_t *arguments;
    size_t argument_count;
} tracer_event_t;

typedef struct tracer_filter {
    const char *class_pattern;
    const char *method_pattern;
    const char *image_pattern;
    bool exclude;
    bool (*custom_filter)(struct tracer_event_t *event, void *context);
    void *custom_filter_context;
} tracer_filter_t;

typedef void (tracer_event_handler_t)(const tracer_event_t *event, void *context);

typedef struct {
    tracer_filter_t filters[32];
    int filter_count;
    tracer_format_options_t format;
    tracer_transport_type_t transport;
    tracer_transport_config_t transport_config;
    tracer_event_handler_t *event_handler;
    void *event_handler_context;
    bool from_dyld_insert;
} tracer_config_t;

typedef enum {
    TRACER_SUCCESS = 0,
    TRACER_ERROR_INVALID_ARGUMENT = -1,
    TRACER_ERROR_INITIALIZATION = -2,
    TRACER_ERROR_MEMORY = -3,
    TRACER_ERROR_RUNTIME = -4,
    TRACER_ERROR_TIMEOUT = -5,
    TRACER_ERROR_ALREADY_INITIALIZED = -6,
} tracer_result_t;

extern tracer_result_t encode_tracer_config(tracer_config_t *config, char **out_str);

@implementation ObjseeTraceRequest
@end

@implementation ObjseeTraceLauncher

- (id)initWithTraceRequest:(ObjseeTraceRequest *)request {
    if ((self = [super init])) {
        self.traceRequest = request;
    }
    
    return self;
}

- (void)launch {
    
    tracer_config_t config = {
        .transport = TRACER_TRANSPORT_STDOUT,
        .from_dyld_insert = true,
    };

    config.format = (tracer_format_options_t) {
        .include_colors = true,
        .include_formatted_trace = true,
        .include_event_json = false,
        .output_as_json = false,
        .include_thread_id = false,
        .include_indents = true,
        .indent_char = " ",
        .include_indent_separators = true,
        .indent_separator_char = "|",
        .variable_separator_spacing = false,
        .static_separator_spacing = 2,
        .include_newline_in_formatted_trace = false,
        .args = TRACER_ARG_FORMAT_DESCRIPTIVE,
    };
    
    for (NSString *classPattern in self.traceRequest.classPatterns) {
        tracer_filter_t filter = {
            .class_pattern = [classPattern UTF8String],
            .method_pattern = "*",
            .image_pattern = NULL,
            .exclude = false,
            .custom_filter = NULL,
            .custom_filter_context = NULL,
        };
        config.filters[config.filter_count++] = filter;
    }
    
    for (NSString *methodPattern in self.traceRequest.methodPatterns) {
        tracer_filter_t filter = {
            .class_pattern = "*",
            .method_pattern = [methodPattern UTF8String],
            .image_pattern = NULL,
            .exclude = false,
            .custom_filter = NULL,
            .custom_filter_context = NULL,
        };
        config.filters[config.filter_count++] = filter;
    }
    
    char *encoded_config = NULL;
    if (encode_tracer_config(&config, (char **)&encoded_config) != TRACER_SUCCESS || encoded_config == NULL) {
        NSLog(@"Failed to encode tracer config");
        return;
    }
    NSString *encodedConfigString = [NSString stringWithUTF8String:encoded_config];
    free(encoded_config);
    
    NSString *libobjseeAssetPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"libobjsee" ofType:@"dylib"];
    NSString *libObjseeTmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"libobjsee.dylib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:libObjseeTmpPath]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:libObjseeTmpPath error:&error];
        if (error) {
            NSLog(@"Failed to remove old libobjsee: %@", error);
            return;
        }
    }
    [[NSFileManager defaultManager] copyItemAtPath:libobjseeAssetPath toPath:libObjseeTmpPath error:nil];
    
    [AppBinaryPatcher codesignItemAtPath:libObjseeTmpPath completion:^(BOOL success, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to codesign libobjsee: %@", error);
            return;
        }

        NSArray *xcrunArgs = @[@"simctl", @"launch", @"--console", @"--terminate-running-process", self.traceRequest.targetDeviceId, self.traceRequest.targetBundleId];
        NSArray *envs = @[
            [NSString stringWithFormat:@"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=%@", libObjseeTmpPath],
            [NSString stringWithFormat:@"SIMCTL_CHILD_OBJSEE_CONFIG=%@", encodedConfigString],
        ];
        
        [TerminalWindowController presentTerminalWithExecutable:@"/usr/bin/xcrun" args:xcrunArgs env:envs title:[NSString stringWithFormat:@"Tracing %@", self.traceRequest.targetBundleId]];
    }];
}

@end
