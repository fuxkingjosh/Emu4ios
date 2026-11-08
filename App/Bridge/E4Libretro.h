// E4Libretro — runs one libretro core (statically linked) behind a small C API
// that mirrors E4Emulator, so the Swift side treats every engine the same way.
//
// Buttons use the RetroPad layout (bit n = RETRO_DEVICE_ID_JOYPAD n):
// B=0 Y=1 Select=2 Start=3 Up=4 Down=5 Left=6 Right=7 A=8 X=9 L=10 R=11 L2=12 R2=13 L3=14 R3=15

#ifndef E4_LIBRETRO_H
#define E4_LIBRETRO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct E4Libretro E4Libretro;

/// `savePath`: memory card / battery file. `systemDir`: where BIOS files may be placed (optional for PS1).
E4Libretro* e4lr_create(const char* contentPath, const char* savePath, const char* systemDir);
void e4lr_destroy(E4Libretro* lr);

void e4lr_video_size(const E4Libretro* lr, unsigned* width, unsigned* height);
double e4lr_fps(const E4Libretro* lr);
double e4lr_sample_rate(const E4Libretro* lr);
double e4lr_aspect_ratio(const E4Libretro* lr);
void e4lr_core_name(char* out, size_t outSize);

void e4lr_set_buttons(E4Libretro* lr, uint32_t retropadMask);
void e4lr_run_frame(E4Libretro* lr);
void e4lr_reset(E4Libretro* lr);

/// Latest frame as RGBX bytes (R,G,B,X), tightly packed width*height.
const uint32_t* e4lr_pixels(const E4Libretro* lr, unsigned* width, unsigned* height);

/// Interleaved stereo Int16 frames produced so far.
size_t e4lr_read_audio(E4Libretro* lr, int16_t* out, size_t maxFrames);

size_t e4lr_state_size(E4Libretro* lr);
bool e4lr_save_state(E4Libretro* lr, void* buffer, size_t size);
bool e4lr_load_state(E4Libretro* lr, const void* buffer, size_t size);
bool e4lr_save_state_file(E4Libretro* lr, const char* path);
bool e4lr_load_state_file(E4Libretro* lr, const char* path);

/// Writes the memory card / battery save to disk (also done on destroy).
void e4lr_flush_save(E4Libretro* lr);

bool e4lr_add_cheat(E4Libretro* lr, const char* code);
void e4lr_clear_cheats(E4Libretro* lr);

#ifdef __cplusplus
}
#endif

#endif
