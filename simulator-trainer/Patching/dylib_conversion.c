//
//  dylib_conversion.c
//  simulator-trainer
//
//  Created by m1book on 5/25/25.
//

#include <libgen.h>
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <libkern/OSByteOrder.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>

#define _FILE_OFFSET_BITS 64

static bool remove_lc_main(uint8_t *commands, uint32_t ncmds, uint32_t *sizeofcmds_ptr) {
    uint8_t *p = commands;
    uint32_t current_offset = 0;
    for (uint32_t i = 0; i < ncmds; i++) {
        struct load_command *lc = (struct load_command *)p;
        if (lc->cmd == LC_MAIN) {
            uint32_t size_to_remove = lc->cmdsize;
            memmove(p, p + size_to_remove, *sizeofcmds_ptr - current_offset - size_to_remove);
            *sizeofcmds_ptr -= size_to_remove;
            return true;
        }
        
        if (lc->cmdsize == 0) {
            return false;
        }

        p += lc->cmdsize;
        current_offset += lc->cmdsize;
    }

    return false;
}

static void patch_pagezero(uint8_t *commands, uint32_t ncmds, uint32_t sizeofcmds) {
    uint8_t *p = commands;
    uint32_t current_offset = 0;
    for (uint32_t i = 0; i < ncmds; i++) {
        struct load_command *lc = (struct load_command *)p;
        if (current_offset + sizeof(struct load_command) > sizeofcmds) {
            break;
        }

        if (lc->cmdsize == 0 || current_offset + lc->cmdsize > sizeofcmds) {
            break;
        }

        if (lc->cmd == LC_SEGMENT_64) {
            if (lc->cmdsize >= sizeof(struct segment_command_64)) {
                struct segment_command_64 *seg = (struct segment_command_64 *)p;
                if (strcmp(seg->segname, "__PAGEZERO") == 0) {
                    strncpy(seg->segname, "__HIBERNATE", sizeof(seg->segname) -1 );
                    seg->segname[sizeof(seg->segname)-1] = '\0';
                    seg->vmsize = 0x4000;
                    seg->vmaddr = 0;
                }
            }
        }

        p += lc->cmdsize;
        current_offset += lc->cmdsize;
    }
}

static bool add_lc_id_dylib(uint8_t *commands, uint32_t *ncmds_ptr, uint32_t *sizeofcmds_ptr, size_t max_sizeofcmds, const char *dylib_path) {
    size_t name_len = strlen(dylib_path) + 1;
    uint32_t padded_size = (uint32_t)((sizeof(struct dylib_command) + name_len + 7) & ~7);

    if (*sizeofcmds_ptr + padded_size > max_sizeofcmds) {
        return false;
    }

    struct dylib_command *idcmd = (struct dylib_command *)(commands + *sizeofcmds_ptr);
    memset(idcmd, 0, padded_size);
    idcmd->cmd = LC_ID_DYLIB;
    idcmd->cmdsize = padded_size;
    idcmd->dylib.name.offset = sizeof(struct dylib_command);
    idcmd->dylib.timestamp = 1;
    idcmd->dylib.current_version = 0x10000;
    idcmd->dylib.compatibility_version = 0x10000;
    memcpy((uint8_t *)idcmd + sizeof(struct dylib_command), dylib_path, name_len);

    *ncmds_ptr += 1;
    *sizeofcmds_ptr += padded_size;
    return true;
}

static bool add_lc_rpath(uint8_t *commands, uint32_t *ncmds_ptr, uint32_t *sizeofcmds_ptr, size_t max_sizeofcmds, const char *dylib_path, const char *new_rpath) {
    size_t name_len = strlen(new_rpath) + 1;
    uint32_t padded_size = (uint32_t)((sizeof(struct rpath_command) + name_len + 7) & ~7);
    if (*sizeofcmds_ptr + padded_size > max_sizeofcmds) {
        printf("Not enough space for LC_RPATH command\n");
        return false;
    }

    struct rpath_command *rpath_cmd = (struct rpath_command *)(commands + *sizeofcmds_ptr);
    memset(rpath_cmd, 0, padded_size);
    rpath_cmd->cmd = LC_RPATH;
    rpath_cmd->cmdsize = padded_size;
    rpath_cmd->path.offset = sizeof(struct rpath_command);
    memcpy((uint8_t *)rpath_cmd + sizeof(struct rpath_command), new_rpath, name_len);

    *ncmds_ptr += 1;
    *sizeofcmds_ptr += padded_size;
    return true;
}

static bool transform_executable_to_dylib(void *mapped_file_slice, size_t slice_size, const char *input_basename) {
    if (slice_size < sizeof(struct mach_header_64)) {
        return false;
    }

    struct mach_header_64 *header = (struct mach_header_64 *)mapped_file_slice;
    if (header->magic != MH_MAGIC_64 || header->filetype != MH_EXECUTE) {
        return false;
    }

    uint8_t *commands_start = (uint8_t *)(header + 1);
    size_t max_cmds_region_size = slice_size - sizeof(struct mach_header_64);
    if (header->sizeofcmds > max_cmds_region_size) {
        return false;
    }

    header->filetype = MH_DYLIB;
    header->flags &= ~MH_PIE;
    header->flags |= MH_NO_REEXPORTED_DYLIBS;

    if (remove_lc_main(commands_start, header->ncmds, &header->sizeofcmds)) {
        header->ncmds--;
    }

    patch_pagezero(commands_start, header->ncmds, header->sizeofcmds);

    char dylib_id_path[PATH_MAX];
    if (strstr(input_basename, ".dylib") == NULL) {
        snprintf(dylib_id_path, sizeof(dylib_id_path), "@rpath/%s.dylib", input_basename);
    }
    else {
        snprintf(dylib_id_path, sizeof(dylib_id_path), "@rpath/%s", input_basename);
    }

    if (!add_lc_id_dylib(commands_start, &header->ncmds, &header->sizeofcmds, max_cmds_region_size, dylib_id_path)) {
        return false;
    }
    
    // add rpath to the dylibs parent dir so stuff sitting next to the dylib get picked up. It expects to be executable, but is now a dylib (diff loading behavior)
    const char *tmp_path = "@loader_path/";
//    getenv("TMPDIR");
//    if (tmp_path == NULL) {
//        tmp_path = "/tmp";
//    }
    add_lc_rpath(commands_start, &header->ncmds, &header->sizeofcmds, max_cmds_region_size, dylib_id_path, tmp_path);
    
    return true;
}

static bool process_macho_slice_for_dylib(FILE *file_ptr, off_t slice_offset, size_t slice_size, const char *base_name_of_input) {
    struct mach_header_64 slice_header_check;
    long original_file_pos = ftell(file_ptr);
    if (original_file_pos == -1) {
        return false;
    }

    if (fseeko(file_ptr, slice_offset, SEEK_SET) != 0) {
        return false;
    }
    
    if (fread(&slice_header_check, sizeof(slice_header_check), 1, file_ptr) != 1) {
        fseeko(file_ptr, original_file_pos, SEEK_SET);
        return false;
    }
    
    if (fseeko(file_ptr, original_file_pos, SEEK_SET) != 0) {
        return false;
    }

    if (slice_header_check.magic != MH_MAGIC_64 || slice_header_check.cputype != CPU_TYPE_ARM64 || slice_header_check.filetype != MH_EXECUTE) {
        return true;
    }

    int file_descriptor = fileno(file_ptr);
    void *mapped_memory_slice = mmap(NULL, slice_size, PROT_READ | PROT_WRITE, MAP_SHARED, file_descriptor, slice_offset);
    if (mapped_memory_slice == MAP_FAILED) {
        return false;
    }

    bool transform_ok = transform_executable_to_dylib(mapped_memory_slice, slice_size, base_name_of_input);
    if (transform_ok) {
        if (msync(mapped_memory_slice, slice_size, MS_SYNC) == -1) {
            transform_ok = false;
        }
    }

    if (munmap(mapped_memory_slice, slice_size) == -1) {
        transform_ok = false;
    }
    
    return transform_ok;
}

static bool process_fat_file_for_dylib(FILE *file, bool needs_byte_swap, struct stat *file_stat, const char *input_path_basename) {
    if (fseeko(file, 0, SEEK_SET) != 0) {
        return false;
    }
    
    struct fat_header fat_hdr;
    if (fread(&fat_hdr, sizeof(fat_hdr), 1, file) != 1) {
        return false;
    }

    uint32_t num_archs = fat_hdr.nfat_arch;
    if (needs_byte_swap) {
        num_archs = OSSwapInt32(num_archs);
    }
    
    if (num_archs == 0 || num_archs > 128) {
        return false;
    }
    
    size_t arch_table_bytes = num_archs * sizeof(struct fat_arch);
    if (sizeof(struct fat_header) + arch_table_bytes > (size_t)file_stat->st_size) {
        return false;
    }
    
    struct fat_arch *architectures = malloc(arch_table_bytes);
    if (architectures == NULL) {
        return false;
    }
    
    if (fread(architectures, sizeof(struct fat_arch), num_archs, file) != num_archs) {
        free(architectures);
        return false;
    }
        
    bool overall_success = true;
    for (uint32_t i = 0; i < num_archs; i++) {
        struct fat_arch current_arch = architectures[i];
        if (needs_byte_swap) {
            current_arch.cputype = OSSwapInt32(current_arch.cputype);
            current_arch.cpusubtype = OSSwapInt32(current_arch.cpusubtype);
            current_arch.offset = OSSwapInt32(current_arch.offset);
            current_arch.size = OSSwapInt32(current_arch.size);
            current_arch.align = OSSwapInt32(current_arch.align);
        }

        if (current_arch.offset < (sizeof(struct fat_header) + arch_table_bytes) || current_arch.offset + current_arch.size > (uint32_t)file_stat->st_size || current_arch.size < sizeof(struct mach_header_64)) {
            overall_success = false;
            continue;
        }

        if (current_arch.cputype == CPU_TYPE_ARM64) {
            if (!process_macho_slice_for_dylib(file, (off_t)current_arch.offset, (size_t)current_arch.size, input_path_basename)) {
                overall_success = false;
            }
        }
    }
    
    free(architectures);
    return overall_success;
}

bool convert_to_dylib_inplace(const char *input_path) {
    if (input_path == NULL) {
        return false;
    }

    char *input_path_copy_for_basename = strdup(input_path);
    if (input_path_copy_for_basename == NULL) {
        return false;
    }

    char *base_name_ptr = basename(input_path_copy_for_basename);
    char *final_basename = strdup(base_name_ptr);
    free(input_path_copy_for_basename);
    if (final_basename == NULL) {
        return false;
    }

    FILE *file = fopen(input_path, "r+b");
    if (!file) {
        free(final_basename);
        return false;
    }
    
    struct stat st;
    if (fstat(fileno(file), &st) != 0) {
        fclose(file);
        free(final_basename);
        return false;
    }

    if (st.st_size < sizeof(uint32_t)) {
        fclose(file);
        free(final_basename);
        return false;
    }

    uint32_t magic_num;
    if (fread(&magic_num, sizeof(magic_num), 1, file) != 1) {
        fclose(file);
        free(final_basename);
        return false;
    }
    
    bool success = false;
    if (magic_num == MH_MAGIC_64 || magic_num == MH_CIGAM_64) {
        if (magic_num == MH_CIGAM_64) {
             success = true;
        }
        else {
            success = process_macho_slice_for_dylib(file, 0, st.st_size, final_basename);
        }
    }
    else if (magic_num == FAT_MAGIC || magic_num == FAT_CIGAM) {
        bool needs_swap = (magic_num == FAT_CIGAM);
        success = process_fat_file_for_dylib(file, needs_swap, &st, final_basename);
    }
    else {
        success = true;
    }
    
    if (fflush(file) != 0) {
        success = false;
    }
    
    if (fclose(file) != 0) {
        success = false;
    }

    free(final_basename);
    return success;
}
