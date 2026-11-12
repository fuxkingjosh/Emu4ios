// E4Libretro — loads libretro cores (each an embedded framework) and runs one at a time behind a small C API
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

/// `corePath`: the core's binary inside the app (Frameworks/<Core>.framework/<Core>).
/// `savePath`: memory card / battery file. `systemDir`: where BIOS files may be placed.
E4Libretro* e4lr_create(const char* corePath, const char* contentPath, const char* savePath, const char* systemDir);
/// Why the last e4lr_create returned NULL (empty if there's nothing to report).
const char* e4lr_last_error(void);
void e4lr_destroy(E4Libretro* lr);

void e4lr_video_size(const E4Libretro* lr, unsigned* width, unsigned* height);
double e4lr_fps(const E4Libretro* lr);
double e4lr_sample_rate(const E4Libretro* lr);
double e4lr_aspect_ratio(const E4Libretro* lr);
void e4lr_core_name(char* out, size_t outSize);

void e4lr_set_buttons(E4Libretro* lr, uint32_t retropadMask);
/// Players 1–4 (port 0–3).
void e4lr_set_port_buttons(E4Libretro* lr, unsigned port, uint32_t retropadMask);
/// stick: 0 = left, 1 = right. Values −32767…32767.
void e4lr_set_analog(E4Libretro* lr, unsigned port, unsigned stick, int16_t x, int16_t y);
/// Touch screen (DS): −32767…32767 across the whole frame.
void e4lr_set_pointer(E4Libretro* lr, int16_t x, int16_t y, bool pressed);
/// Computer cores: relative mouse movement and buttons.
void e4lr_mouse(E4Libretro* lr, int16_t dx, int16_t dy, bool left, bool right);
/// Computer cores: libretro key code (RETROK_*), pressed state, Unicode character.
void e4lr_key(E4Libretro* lr, unsigned keycode, bool down, uint32_t character, uint16_t modifiers);
/// True for cores that draw with OpenGL ES (N64, PSP).
bool e4lr_uses_gpu(const E4Libretro* lr);

/// Core options, applied the next time a core asks (call before e4lr_create).
void e4lr_set_option(const char* key, const char* value);
void e4lr_clear_options(void);

/// Emulated memory for RetroAchievements.
size_t e4lr_memory_map_count(const E4Libretro* lr);
const void* e4lr_memory_map(const E4Libretro* lr);
uint8_t* e4lr_memory(unsigned id, size_t* size);
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
