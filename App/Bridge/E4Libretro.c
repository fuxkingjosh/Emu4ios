#include "E4Libretro.h"
#include "libretro.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// libretro callbacks have no user pointer, so only one core runs at a time (that's all we need).
struct E4Libretro {
    struct retro_system_av_info av;
    enum retro_pixel_format format;
    uint32_t* video;            // RGBX, tightly packed
    unsigned width, height;
    size_t videoCapacity;

    int16_t* audio;             // ring buffer, interleaved stereo
    size_t audioCapacity;       // in frames
    size_t audioRead, audioWrite, audioCount;

    uint32_t buttons;
    char savePath[1024];
    char systemDir[1024];
    unsigned cheatIndex;
    bool loaded;
};

static E4Libretro* current = NULL;

// MARK: - Callbacks

static void log_cb(enum retro_log_level level, const char* fmt, ...) {
    (void) level; (void) fmt;
}

static bool environment_cb(unsigned cmd, void* data) {
    E4Libretro* lr = current;
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback*) data)->log = log_cb;
        return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        enum retro_pixel_format fmt = *(const enum retro_pixel_format*) data;
        if (fmt == RETRO_PIXEL_FORMAT_XRGB8888 || fmt == RETRO_PIXEL_FORMAT_RGB565 || fmt == RETRO_PIXEL_FORMAT_0RGB1555) {
            if (lr) lr->format = fmt;
            return true;
        }
        return false;
    }
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char**) data = lr ? lr->systemDir : NULL;
        return lr != NULL;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool*) data = true;
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable* var = data;
        // Sensible PS1 defaults; everything else uses the core's own defaults.
        if (var && var->key) {
            if (!strcmp(var->key, "pcsx_rearmed_bios")) { var->value = "auto"; return true; }
            if (!strcmp(var->key, "pcsx_rearmed_show_bios_bootlogo")) { var->value = "disabled"; return true; }
            if (!strcmp(var->key, "pcsx_rearmed_frameskip_type")) { var->value = "disabled"; return true; }
        }
        return false;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool*) data = false;
        return true;
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
        if (lr && data) lr->av.geometry = *(const struct retro_game_geometry*) data;
        return true;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
        if (lr && data) lr->av = *(const struct retro_system_av_info*) data;
        return true;
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        *(unsigned*) data = 0;
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
        *(unsigned*) data = RETRO_LANGUAGE_ENGLISH;
        return true;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        return true;
    default:
        return false;
    }
}

static void ensure_video(E4Libretro* lr, unsigned w, unsigned h) {
    size_t need = (size_t) w * h;
    if (need > lr->videoCapacity) {
        free(lr->video);
        lr->video = calloc(need, sizeof(uint32_t));
        lr->videoCapacity = need;
    }
    lr->width = w;
    lr->height = h;
}

static void video_cb(const void* data, unsigned width, unsigned height, size_t pitch) {
    E4Libretro* lr = current;
    if (!lr || !data || width == 0 || height == 0) return; // NULL = duplicate frame: keep the last one
    ensure_video(lr, width, height);
    uint32_t* out = lr->video;
    for (unsigned y = 0; y < height; y++) {
        const uint8_t* row = (const uint8_t*) data + y * pitch;
        uint32_t* dst = out + (size_t) y * width;
        if (lr->format == RETRO_PIXEL_FORMAT_XRGB8888) {
            const uint32_t* src = (const uint32_t*) row;
            for (unsigned x = 0; x < width; x++) {
                uint32_t p = src[x]; // 0x00RRGGBB
                dst[x] = ((p >> 16) & 0xFF) | (p & 0xFF00) | ((p & 0xFF) << 16) | 0xFF000000u;
            }
        } else if (lr->format == RETRO_PIXEL_FORMAT_RGB565) {
            const uint16_t* src = (const uint16_t*) row;
            for (unsigned x = 0; x < width; x++) {
                uint16_t p = src[x];
                uint32_t r = (p >> 11) & 0x1F, g = (p >> 5) & 0x3F, b = p & 0x1F;
                r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
                dst[x] = r | (g << 8) | (b << 16) | 0xFF000000u;
            }
        } else {
            const uint16_t* src = (const uint16_t*) row;
            for (unsigned x = 0; x < width; x++) {
                uint16_t p = src[x];
                uint32_t r = (p >> 10) & 0x1F, g = (p >> 5) & 0x1F, b = p & 0x1F;
                r = (r << 3) | (r >> 2); g = (g << 3) | (g >> 2); b = (b << 3) | (b >> 2);
                dst[x] = r | (g << 8) | (b << 16) | 0xFF000000u;
            }
        }
    }
}

static size_t audio_batch_cb(const int16_t* data, size_t frames) {
    E4Libretro* lr = current;
    if (!lr || !lr->audio) return frames;
    for (size_t i = 0; i < frames; i++) {
        size_t w = lr->audioWrite * 2;
        lr->audio[w] = data[i * 2];
        lr->audio[w + 1] = data[i * 2 + 1];
        lr->audioWrite = (lr->audioWrite + 1) % lr->audioCapacity;
        if (lr->audioCount == lr->audioCapacity) {
            lr->audioRead = (lr->audioRead + 1) % lr->audioCapacity; // drop oldest
        } else {
            lr->audioCount++;
        }
    }
    return frames;
}

static void audio_sample_cb(int16_t left, int16_t right) {
    int16_t frame[2] = { left, right };
    audio_batch_cb(frame, 1);
}

static void input_poll_cb(void) {}

static int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    E4Libretro* lr = current;
    (void) index;
    if (!lr || port != 0 || device != RETRO_DEVICE_JOYPAD) return 0;
    if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t) (lr->buttons & 0xFFFF);
    return (lr->buttons >> id) & 1;
}

// MARK: - Save data

static void load_save(E4Libretro* lr) {
    size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    void* mem = retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if (!size || !mem || !lr->savePath[0]) return;
    FILE* f = fopen(lr->savePath, "rb");
    if (!f) return;
    fread(mem, 1, size, f);
    fclose(f);
}

void e4lr_flush_save(E4Libretro* lr) {
    if (!lr || !lr->loaded) return;
    size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    void* mem = retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if (!size || !mem || !lr->savePath[0]) return;
    FILE* f = fopen(lr->savePath, "wb");
    if (!f) return;
    fwrite(mem, 1, size, f);
    fclose(f);
}

// MARK: - Lifecycle

static bool coreInitialized = false;

E4Libretro* e4lr_create(const char* contentPath, const char* savePath, const char* systemDir) {
    if (current) return NULL;
    E4Libretro* lr = calloc(1, sizeof(*lr));
    lr->format = RETRO_PIXEL_FORMAT_0RGB1555;
    snprintf(lr->savePath, sizeof(lr->savePath), "%s", savePath ? savePath : "");
    snprintf(lr->systemDir, sizeof(lr->systemDir), "%s", systemDir ? systemDir : "");
    current = lr;

    retro_set_environment(environment_cb);
    retro_set_video_refresh(video_cb);
    retro_set_audio_sample(audio_sample_cb);
    retro_set_audio_sample_batch(audio_batch_cb);
    retro_set_input_poll(input_poll_cb);
    retro_set_input_state(input_state_cb);
    if (!coreInitialized) {
        retro_init();
        coreInitialized = true;
    }
    retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);

    struct retro_game_info info = { .path = contentPath, .data = NULL, .size = 0, .meta = NULL };
    if (!retro_load_game(&info)) {
        current = NULL;
        free(lr);
        return NULL;
    }
    lr->loaded = true;
    retro_get_system_av_info(&lr->av);
    lr->audioCapacity = (size_t) (lr->av.timing.sample_rate > 0 ? lr->av.timing.sample_rate : 44100) / 2;
    lr->audio = calloc(lr->audioCapacity * 2, sizeof(int16_t));
    ensure_video(lr, lr->av.geometry.base_width ? lr->av.geometry.base_width : 320,
                 lr->av.geometry.base_height ? lr->av.geometry.base_height : 240);
    load_save(lr);
    return lr;
}

void e4lr_destroy(E4Libretro* lr) {
    if (!lr) return;
    e4lr_flush_save(lr);
    if (lr->loaded) retro_unload_game();
    // Keep the core initialized between games (some cores don't like deinit/init cycles).
    if (current == lr) current = NULL;
    free(lr->video);
    free(lr->audio);
    free(lr);
}

// MARK: - Info

void e4lr_video_size(const E4Libretro* lr, unsigned* width, unsigned* height) {
    if (width) *width = lr->width;
    if (height) *height = lr->height;
}

double e4lr_fps(const E4Libretro* lr) { return lr->av.timing.fps > 1 ? lr->av.timing.fps : 60; }
double e4lr_sample_rate(const E4Libretro* lr) { return lr->av.timing.sample_rate > 0 ? lr->av.timing.sample_rate : 44100; }

double e4lr_aspect_ratio(const E4Libretro* lr) {
    float a = lr->av.geometry.aspect_ratio;
    if (a > 0.1f) return a;
    return lr->av.geometry.base_height ? (double) lr->av.geometry.base_width / lr->av.geometry.base_height : 4.0 / 3.0;
}

void e4lr_core_name(char* out, size_t outSize) {
    struct retro_system_info info;
    memset(&info, 0, sizeof(info));
    retro_get_system_info(&info);
    snprintf(out, outSize, "%s %s", info.library_name ? info.library_name : "", info.library_version ? info.library_version : "");
}

// MARK: - Running

void e4lr_set_buttons(E4Libretro* lr, uint32_t mask) { lr->buttons = mask; }

void e4lr_run_frame(E4Libretro* lr) {
    current = lr;
    retro_run();
}

void e4lr_reset(E4Libretro* lr) { (void) lr; retro_reset(); }

const uint32_t* e4lr_pixels(const E4Libretro* lr, unsigned* width, unsigned* height) {
    if (width) *width = lr->width;
    if (height) *height = lr->height;
    return lr->video;
}

size_t e4lr_read_audio(E4Libretro* lr, int16_t* out, size_t maxFrames) {
    size_t n = lr->audioCount < maxFrames ? lr->audioCount : maxFrames;
    for (size_t i = 0; i < n; i++) {
        out[i * 2] = lr->audio[lr->audioRead * 2];
        out[i * 2 + 1] = lr->audio[lr->audioRead * 2 + 1];
        lr->audioRead = (lr->audioRead + 1) % lr->audioCapacity;
    }
    lr->audioCount -= n;
    return n;
}

// MARK: - States

size_t e4lr_state_size(E4Libretro* lr) { (void) lr; return retro_serialize_size(); }

bool e4lr_save_state(E4Libretro* lr, void* buffer, size_t size) {
    (void) lr;
    return retro_serialize(buffer, size);
}

bool e4lr_load_state(E4Libretro* lr, const void* buffer, size_t size) {
    (void) lr;
    return retro_unserialize(buffer, size);
}

bool e4lr_save_state_file(E4Libretro* lr, const char* path) {
    size_t size = e4lr_state_size(lr);
    if (!size) return false;
    void* buf = malloc(size);
    bool ok = e4lr_save_state(lr, buf, size);
    if (ok) {
        FILE* f = fopen(path, "wb");
        ok = f && fwrite(buf, 1, size, f) == size;
        if (f) fclose(f);
    }
    free(buf);
    e4lr_flush_save(lr);
    return ok;
}

bool e4lr_load_state_file(E4Libretro* lr, const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size <= 0) { fclose(f); return false; }
    void* buf = malloc((size_t) size);
    bool ok = fread(buf, 1, (size_t) size, f) == (size_t) size;
    fclose(f);
    if (ok) ok = e4lr_load_state(lr, buf, (size_t) size);
    free(buf);
    return ok;
}

// MARK: - Cheats

bool e4lr_add_cheat(E4Libretro* lr, const char* code) {
    if (!code || !code[0]) return false;
    // Codes may be pasted one per line; libretro wants them joined with '+'.
    char* joined = strdup(code);
    for (char* p = joined; *p; p++) if (*p == '\n' || *p == '\r') *p = '+';
    retro_cheat_set(lr->cheatIndex++, true, joined);
    free(joined);
    return true;
}

void e4lr_clear_cheats(E4Libretro* lr) {
    retro_cheat_reset();
    lr->cheatIndex = 0;
}
