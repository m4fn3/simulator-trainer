//
//  platform_changer.h
//  simforge
//
//  Created by Ethan Arbuckle on 1/18/25.
//

#import <Foundation/Foundation.h>

/**
  * Add the Simulator platform tag (7) into a single non-fat arm64 macho file's LC_BUILD_VERSION
  * @param filepath The path to the macho file
  * @return YES if the file was patched successfully, NO otherwise
 */
BOOL convertPlatformToSimulator_single(const char *filepath);

/**
  * Add the Simulator platform tag (7) into binaries within a bundle/directory
  * @param dirpath The path to the bundle/directory
 */
void convertPlatformToSimulator(const char *dirpath);
