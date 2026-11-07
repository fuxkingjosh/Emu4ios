// E4Emulator — a small, stable C API over the mGBA core.
// Swift only ever talks to these functions, so swapping or adding
// emulator cores later never touches the UI code.

#ifndef E4_EMULATOR_H
#define E4_EMULATOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct E4Emulator E4Emulator;

typedef enum {
    E4SystemUnknown = 0,
    E4SystemGB = 1,
    E4SystemGBC = 2,
    E4SystemGBA = 3,
} E4System;

// Button bits. GB/GBC simply ignore L and R.
typedef enum {
    E4ButtonA      = 1 << 0,
    E4ButtonB      = 1 << 1,
    E4ButtonSelect = 1 << 2,
    E4ButtonStart  = 1 << 3,
    E4ButtonRight  = 1 << 4,
    E4ButtonLeft   = 1 << 5,
    E4ButtonUp     = 1 << 6,
    E4ButtonDown   = 1 << 7,
    E4ButtonR      = 1 << 8,
    E4ButtonL      = 1 << 9,
} E4Button;

/// Loads a ROM from disk. `savePath` is where battery saves live (created if missing).
/// Returns NULL if the file is not a supported game.
E4Emulator* e4_create(const char* romPath, const char* savePath);
void e4_destroy(E4Emulator* emu);

E4System e4_system(const E4Emulator* emu);
void e4_video_size(const E4Emulator* emu, unsigned* width, unsigned* height);
double e4_fps(const E4Emulator* emu);
unsigned e4_sample_rate(const E4Emulator* emu);

/// Game title from the ROM header (may be empty).
void e4_title(const E4Emulator* emu, char* out, size_t outSize);

void e4_set_buttons(E4Emulator* emu, uint32_t buttons);
void e4_run_frame(E4Emulator* emu);
void e4_reset(E4Emulator* emu);

/// Pixels are 32-bit, little-endian XBGR (byte order R,G,B,X), `stride` in pixels.
const uint32_t* e4_pixels(const E4Emulator* emu, size_t* stride);

/// Reads interleaved stereo int16 samples produced so far. Returns number of frames (L+R pairs).
size_t e4_read_audio(E4Emulator* emu, int16_t* out, size_t maxFrames);

/// Save states. `withSaveData` also embeds the battery save (use for user slots, not for rewind).
size_t e4_state_size(E4Emulator* emu);
bool e4_save_state(E4Emulator* emu, void* buffer, size_t size, size_t* written, bool withSaveData);
bool e4_load_state(E4Emulator* emu, const void* buffer, size_t size);

/// Saves a state to a file, and a PNG-free raw screenshot is taken by Swift from e4_pixels.
bool e4_save_state_file(E4Emulator* emu, const char* path);
bool e4_load_state_file(E4Emulator* emu, const char* path);

/// Cheats (GameShark / Action Replay / Game Genie codes). Returns false if the code was rejected.
bool e4_add_cheat(E4Emulator* emu, const char* name, const char* code);
void e4_clear_cheats(E4Emulator* emu);

/// Reads one byte of emulated memory (used by RetroAchievements later).
uint8_t e4_peek(E4Emulator* emu, uint32_t address);

#ifdef __cplusplus
}
#endif

#endif
