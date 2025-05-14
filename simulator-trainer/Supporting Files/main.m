//
//  main.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>
#import <libobjsee/tracer.h>
#import <dlfcn.h>


//void event_handler(const tracer_event_t *event, void *context) {
//    // Handle or log the event here
//    // You can format it as JSON or colorized text, depending on tracer_format_options_t
//    printf("Traced event: class=%s, method=%s\n", event->class_name, event->method_name);
//    printf("%s", event->formatted_output);
//}


@interface ObjcLaunch : NSObject
@end

int main();

@implementation ObjcLaunch

+ (void)load {
    return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        tracer_error_t *error = NULL;
        tracer_t *tracer = tracer_create_with_error(&error);
        if (!tracer) {
            printf("Error creating tracer: %s\n", error->message);
            free_error(error);
            return;
        }
        
        tracer_format_options_t format = {
            .include_formatted_trace = false,
            .include_event_json = true,
            .output_as_json = true,
            .include_colors = false,
            .include_thread_id = true,
            .args = TRACER_ARG_FORMAT_NONE,
            .include_indents = true,
            .include_indent_separators = true,
            .variable_separator_spacing = false,
            .static_separator_spacing = 4,
            .indent_char = ".",
            .indent_separator_char = "|",
            .include_newline_in_formatted_trace = true
        };
        tracer_set_format_options(tracer, format);
        
        Dl_info info;
        if (dladdr((void *)main, &info) && info.dli_fname) {
            printf("filtrering to image: %s\n", info.dli_fname);
            tracer_include_image(tracer, info.dli_fname);
        }
        
//        tracer_set_output_handler(tracer, event_handler, NULL);
             tracer_set_output_stdout(tracer);
        
        if (tracer_start(tracer) != TRACER_SUCCESS) {
            printf("Failed to start tracer: %s\n", tracer_get_last_error(tracer));
            tracer_cleanup(tracer);
            return;
        }
        
        printf("tracer started\n");
    });
}

@end

int main(int argc, const char * argv[]) {
    
    dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/CoreSimulator", 0);
    
//    @autoreleasepool {
        
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
//            tracer_error_t *error = NULL;
//            tracer_t *tracer = tracer_create_with_error(&error);
//            if (!tracer) {
//                printf("Error creating tracer: %s\n", error->message);
//                free_error(error);
//                return 1;
//            }
//            
//            tracer_format_options_t format = {
//                .include_formatted_trace = true,
//                .include_event_json = false,
//                .output_as_json = false,
//                .include_colors = false,
//                .include_thread_id = true,
//                .args = TRACER_ARG_FORMAT_BASIC,
//                .include_indents = true,
//                .include_indent_separators = true,
//                .variable_separator_spacing = false,
//                .static_separator_spacing = 4,
//                .indent_char = ".",
//                .indent_separator_char = "|",
//                .include_newline_in_formatted_trace = true
//            };
//            tracer_set_format_options(tracer, format);
//            
////            tracer_set_output_handler(tracer, event_handler, NULL);
//            // Or, send to stdout
//             tracer_set_output_stdout(tracer);
//            
//            if (tracer_start(tracer) != TRACER_SUCCESS) {
//                printf("Failed to start tracer: %s\n", tracer_get_last_error(tracer));
//                tracer_cleanup(tracer);
//                return 1;
//            }
//        });
//    }

    return NSApplicationMain(argc, argv);
}
