#include <stdarg.h>
#include "E4Libretro.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

/// Debug output for the Linux test harness (E4_LOG=1); silent in the app.
static void e4lr_debug(const char* fmt, ...) {
#ifndef __APPLE__
    if (!getenv("E4_LOG")) return;
    va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
#else
    (void) fmt;
#endif
}
#include "libretro.h"
#ifdef __APPLE__
#include "E4GL.h"
#endif

#include <dlfcn.h>
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

    uint32_t buttons;              // port 0 (kept for compatibility)
    uint32_t portButtons[4];
    int16_t analog[4][2][2];       // [port][stick: 0 left, 1 right][axis: 0 x, 1 y]
    int16_t pointerX, pointerY;    // -0x7fff…0x7fff over the whole frame
    bool pointerPressed;
    int16_t mouseDX, mouseDY;
    bool mouseLeft, mouseRight;
    uint8_t keys[RETROK_LAST];
    retro_keyboard_event_t keyboardCallback;
    struct retro_hw_render_callback hw;
    bool usesHW;
#ifdef __APPLE__
    E4GL* gl;
#endif
    struct retro_memory_descriptor* memoryMap;
    unsigned memoryMapCount;
    char savePath[1024];
    char saveDir[1024];
    char systemDir[1024];
    void* contentData;          // ROM bytes for cores that don't read files themselves
    unsigned cheatIndex;
    bool loaded;
};

static E4Libretro* current = NULL;

// Core options chosen by the app (key → value). Anything not set uses the core's default.
#define MAX_OPTIONS 128
static char optionKeys[MAX_OPTIONS][96];
static char optionValues[MAX_OPTIONS][128];
static int optionCount = 0;

void e4lr_set_option(const char* key, const char* value) {
    for (int i = 0; i < optionCount; i++) {
        if (!strcmp(optionKeys[i], key)) { snprintf(optionValues[i], sizeof optionValues[i], "%s", value); return; }
    }
    if (optionCount >= MAX_OPTIONS) return;
    snprintf(optionKeys[optionCount], sizeof optionKeys[0], "%s", key);
    snprintf(optionValues[optionCount], sizeof optionValues[0], "%s", value);
    optionCount++;
}

void e4lr_clear_options(void) { optionCount = 0; }

// What the core itself declares: each option's default and allowed values ("a|b|c"), like RetroArch keeps.
// (stored per core in CoreAPI, since some cores only declare them once in retro_init)
static void declare_option(const char* key, const char* def, const char* allowed);

static bool value_allowed(const char* allowed, const char* value) {
    if (!allowed[0]) return true; // unknown list: trust the app
    size_t n = strlen(value);
    for (const char* p = allowed; *p; ) {
        const char* end = strchr(p, '|');
        size_t len = end ? (size_t) (end - p) : strlen(p);
        if (len == n && !strncmp(p, value, n)) return true;
        if (!end) break;
        p = end + 1;
    }
    return false;
}

static const char* find_option(const char* key);

/// Builds "a|b|c" from a core option value list.
static void join_values(const struct retro_core_option_value* values, char* out, size_t outSize) {
    out[0] = 0;
    for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX && values[i].value; i++) {
        if (i) strncat(out, "|", outSize - strlen(out) - 1);
        strncat(out, values[i].value, outSize - strlen(out) - 1);
    }
}

static void declare_v1(const struct retro_core_option_definition* defs) {
    char allowed[4096];
    for (; defs && defs->key; defs++) {
        join_values(defs->values, allowed, sizeof allowed);
        declare_option(defs->key, defs->default_value ? defs->default_value : defs->values[0].value, allowed);
    }
}

static void declare_v2(const struct retro_core_options_v2* opts) {
    char allowed[4096];
    if (!opts) return;
    for (const struct retro_core_option_v2_definition* d = opts->definitions; d && d->key; d++) {
        join_values(d->values, allowed, sizeof allowed);
        declare_option(d->key, d->default_value ? d->default_value : d->values[0].value, allowed);
    }
}

/// Old-style "Description; default|other|values".
static void declare_variables(const struct retro_variable* vars) {
    for (; vars && vars->key; vars++) {
        const char* semi = vars->value ? strstr(vars->value, "; ") : NULL;
        if (!semi) continue;
        const char* list = semi + 2;
        const char* bar = strchr(list, '|');
        char def[256];
        size_t len = bar ? (size_t) (bar - list) : strlen(list);
        if (len >= sizeof def) len = sizeof def - 1;
        memcpy(def, list, len); def[len] = 0;
        declare_option(vars->key, def, list);
    }
}

#ifdef __APPLE__
static uintptr_t hw_get_framebuffer(void) { return current && current->gl ? e4gl_framebuffer(current->gl) : 0; }
static retro_proc_address_t hw_get_proc(const char* sym) { return (retro_proc_address_t) e4gl_proc_address(sym); }
#endif

// The core's libretro functions, looked up from its embedded framework.
typedef struct {
    void* handle;
    char path[1024];
    bool initialized;
    void (*set_environment)(retro_environment_t);
    void (*set_video_refresh)(retro_video_refresh_t);
    void (*set_audio_sample)(retro_audio_sample_t);
    void (*set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*set_input_poll)(retro_input_poll_t);
    void (*set_input_state)(retro_input_state_t);
    void (*init)(void);
    void (*get_system_info)(struct retro_system_info*);
    void (*get_system_av_info)(struct retro_system_av_info*);
    void (*set_controller_port_device)(unsigned, unsigned);
    void (*reset)(void);
    void (*run)(void);
    size_t (*serialize_size)(void);
    bool (*serialize)(void*, size_t);
    bool (*unserialize)(const void*, size_t);
    void (*cheat_reset)(void);
    void (*cheat_set)(unsigned, bool, const char*);
    bool (*load_game)(const struct retro_game_info*);
    void (*unload_game)(void);
    void* (*get_memory_data)(unsigned);
    size_t (*get_memory_size)(unsigned);
    int declaredCount;
    char* declaredKeys[512];
    char* declaredDefaults[512];
    char* declaredValues[512];
} CoreAPI;

#define MAX_CORES 16
static CoreAPI cores[MAX_CORES];
static int coreCount = 0;
static CoreAPI* api = NULL; // core of the running game

static void declare_option(const char* key, const char* def, const char* allowed) {
    if (!key || !api) return;
    for (int i = 0; i < api->declaredCount; i++) if (!strcmp(api->declaredKeys[i], key)) return;
    if (api->declaredCount >= 512) return;
    int n = api->declaredCount++;
    api->declaredKeys[n] = strdup(key);
    api->declaredDefaults[n] = strdup(def ? def : "");
    api->declaredValues[n] = strdup(allowed ? allowed : "");
}

static const char* find_option(const char* key) {
    int d = -1;
    if (api) for (int i = 0; i < api->declaredCount; i++) if (!strcmp(api->declaredKeys[i], key)) { d = i; break; }
    for (int i = 0; i < optionCount; i++) {
        if (strcmp(optionKeys[i], key)) continue;
        // Ignore a setting the core doesn't accept (it would otherwise fall into undefined territory).
        if (d < 0 || value_allowed(api->declaredValues[d], optionValues[i])) return optionValues[i];
        break;
    }
    return d >= 0 ? api->declaredDefaults[d] : NULL;
}

static CoreAPI* load_core(const char* path) {
    for (int i = 0; i < coreCount; i++) {
        if (!strcmp(cores[i].path, path)) return &cores[i];
    }
    if (coreCount >= MAX_CORES) return NULL;
    void* h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) { e4lr_debug("dlopen failed: %s\n", dlerror()); return NULL; }
    CoreAPI* c = &cores[coreCount];
    memset(c, 0, sizeof(*c));
    c->handle = h;
    snprintf(c->path, sizeof(c->path), "%s", path);
#define SYM(field, name) c->field = dlsym(h, name); if (!c->field) { dlclose(h); return NULL; }
    SYM(set_environment, "retro_set_environment")
    SYM(set_video_refresh, "retro_set_video_refresh")
    SYM(set_audio_sample, "retro_set_audio_sample")
    SYM(set_audio_sample_batch, "retro_set_audio_sample_batch")
    SYM(set_input_poll, "retro_set_input_poll")
    SYM(set_input_state, "retro_set_input_state")
    SYM(init, "retro_init")
    SYM(get_system_info, "retro_get_system_info")
    SYM(get_system_av_info, "retro_get_system_av_info")
    SYM(set_controller_port_device, "retro_set_controller_port_device")
    SYM(reset, "retro_reset")
    SYM(run, "retro_run")
    SYM(serialize_size, "retro_serialize_size")
    SYM(serialize, "retro_serialize")
    SYM(unserialize, "retro_unserialize")
    SYM(cheat_reset, "retro_cheat_reset")
    SYM(cheat_set, "retro_cheat_set")
    SYM(load_game, "retro_load_game")
    SYM(unload_game, "retro_unload_game")
    SYM(get_memory_data, "retro_get_memory_data")
    SYM(get_memory_size, "retro_get_memory_size")
#undef SYM
    coreCount++;
    return c;
}

// MARK: - Callbacks

static void log_cb(enum retro_log_level level, const char* fmt, ...) {
#ifndef __APPLE__
    if (getenv("E4_LOG")) { va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap); }
#endif
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
        *(const char**) data = lr ? lr->systemDir : NULL;
        return lr != NULL;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        // Cores that manage their own save files (DOS, Amiga, C64, DS) keep them next to the game's save.
        *(const char**) data = lr ? (lr->saveDir[0] ? lr->saveDir : lr->systemDir) : NULL;
        return lr != NULL;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool*) data = true;
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable* var = data;
        if (var && var->key) {
            const char* v = find_option(var->key);
            if (v) { var->value = v; return true; }
        }
        return false;
    }
    case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK:
        if (lr && data) lr->keyboardCallback = ((const struct retro_keyboard_callback*) data)->callback;
        return true;
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
        if (lr && data) {
            const struct retro_memory_map* map = data;
            free(lr->memoryMap);
            lr->memoryMapCount = map->num_descriptors;
            lr->memoryMap = calloc(map->num_descriptors, sizeof(struct retro_memory_descriptor));
            memcpy(lr->memoryMap, map->descriptors, map->num_descriptors * sizeof(struct retro_memory_descriptor));
        }
        return true;
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
#ifdef __APPLE__
        struct retro_hw_render_callback* cb = data;
        if (!lr || !cb) return false;
        if (cb->context_type != RETRO_HW_CONTEXT_OPENGLES2 && cb->context_type != RETRO_HW_CONTEXT_OPENGLES3 &&
            cb->context_type != RETRO_HW_CONTEXT_OPENGLES_VERSION) return false;
        cb->get_current_framebuffer = hw_get_framebuffer;
        cb->get_proc_address = hw_get_proc;
        lr->hw = *cb;
        lr->usesHW = true;
        return true;
#else
        return false;
#endif
    }
    case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
        *(unsigned*) data = RETRO_HW_CONTEXT_OPENGLES3;
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_DEVICE_CAPABILITIES:
        *(uint64_t*) data = (1 << RETRO_DEVICE_JOYPAD) | (1 << RETRO_DEVICE_ANALOG) | (1 << RETRO_DEVICE_POINTER) |
                            (1 << RETRO_DEVICE_KEYBOARD) | (1 << RETRO_DEVICE_MOUSE);
        return true;
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
        *(unsigned*) data = 2;
        return true;
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        declare_variables(data);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
        declare_v1(data);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL:
        if (data) declare_v1(((const struct retro_core_options_intl*) data)->us);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
        declare_v2(data);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
        if (data) declare_v2(((const struct retro_core_options_v2_intl*) data)->us);
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true;
    case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
        *(const char**) data = lr ? lr->systemDir : NULL;
        return lr != NULL;
    case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
        *(int*) data = 3;
        return true;
    case RETRO_ENVIRONMENT_GET_FASTFORWARDING:
        *(bool*) data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION:
        *(unsigned*) data = 0;
        return true;
    case RETRO_ENVIRONMENT_SET_MESSAGE:
    case RETRO_ENVIRONMENT_SET_MESSAGE_EXT:
    case RETRO_ENVIRONMENT_SET_ROTATION:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
    case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
    case RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY:
    case RETRO_ENVIRONMENT_SET_AUDIO_BUFFER_STATUS_CALLBACK:
        return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
        *(unsigned*) data = RETRO_LANGUAGE_ENGLISH;
        return true;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
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
#ifdef __APPLE__
    if (lr && data == RETRO_HW_FRAME_BUFFER_VALID && lr->gl && width && height) {
        ensure_video(lr, width, height);
        e4gl_read(lr->gl, width, height, lr->hw.bottom_left_origin, lr->video);
        return;
    }
#endif
    if (!lr || !data || data == RETRO_HW_FRAME_BUFFER_VALID || width == 0 || height == 0) return; // NULL = duplicate frame
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
    if (!lr || port > 3) return 0;
    switch (device & RETRO_DEVICE_MASK) {
    case RETRO_DEVICE_JOYPAD: {
        uint32_t b = lr->portButtons[port];
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t) (b & 0xFFFF);
        return (b >> id) & 1;
    }
    case RETRO_DEVICE_ANALOG:
        if (index <= RETRO_DEVICE_INDEX_ANALOG_RIGHT && id <= RETRO_DEVICE_ID_ANALOG_Y) return lr->analog[port][index][id];
        if (index == RETRO_DEVICE_INDEX_ANALOG_BUTTON) return ((lr->portButtons[port] >> id) & 1) ? 0x7fff : 0;
        return 0;
    case RETRO_DEVICE_POINTER:
        if (port != 0 || index != 0) return 0;
        if (id == RETRO_DEVICE_ID_POINTER_X) return lr->pointerX;
        if (id == RETRO_DEVICE_ID_POINTER_Y) return lr->pointerY;
        if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return lr->pointerPressed;
        if (id == RETRO_DEVICE_ID_POINTER_COUNT) return lr->pointerPressed ? 1 : 0;
        return 0;
    case RETRO_DEVICE_KEYBOARD:
        return (port == 0 && id < RETROK_LAST) ? lr->keys[id] : 0;
    case RETRO_DEVICE_MOUSE: {
        if (port != 0) return 0;
        int16_t v = 0;
        if (id == RETRO_DEVICE_ID_MOUSE_X) { v = lr->mouseDX; lr->mouseDX = 0; }
        else if (id == RETRO_DEVICE_ID_MOUSE_Y) { v = lr->mouseDY; lr->mouseDY = 0; }
        else if (id == RETRO_DEVICE_ID_MOUSE_LEFT) v = lr->mouseLeft;
        else if (id == RETRO_DEVICE_ID_MOUSE_RIGHT) v = lr->mouseRight;
        return v;
    }
    default:
        return 0;
    }
}

static void enter(E4Libretro* lr);

// MARK: - Save data

static void load_save(E4Libretro* lr) {
    size_t size = api->get_memory_size(RETRO_MEMORY_SAVE_RAM);
    void* mem = api->get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if (!size || !mem || !lr->savePath[0]) return;
    FILE* f = fopen(lr->savePath, "rb");
    if (!f) return;
    fread(mem, 1, size, f);
    fclose(f);
}

void e4lr_flush_save(E4Libretro* lr) {
    if (!lr || !lr->loaded) return;
    enter(lr);
    size_t size = api->get_memory_size(RETRO_MEMORY_SAVE_RAM);
    void* mem = api->get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if (!size || !mem || !lr->savePath[0]) return;
    FILE* f = fopen(lr->savePath, "wb");
    if (!f) return;
    fwrite(mem, 1, size, f);
    fclose(f);
}

// MARK: - Lifecycle

E4Libretro* e4lr_create(const char* corePath, const char* contentPath, const char* savePath, const char* systemDir) {
    if (current) { e4lr_debug("a game is already running\n"); return NULL; }
    CoreAPI* core = load_core(corePath);
    if (!core) return NULL;
    api = core;
    E4Libretro* lr = calloc(1, sizeof(*lr));
    lr->format = RETRO_PIXEL_FORMAT_0RGB1555;
    snprintf(lr->savePath, sizeof(lr->savePath), "%s", savePath ? savePath : "");
    snprintf(lr->systemDir, sizeof(lr->systemDir), "%s", systemDir ? systemDir : "");
    snprintf(lr->saveDir, sizeof(lr->saveDir), "%s", lr->savePath);
    char* slash = strrchr(lr->saveDir, '/');
    if (slash) {
        // Saves/Core Saves: where cores that write their own files (DOS, Amiga, C64, DS) put them.
        *slash = 0;
        strncat(lr->saveDir, "/Core Saves", sizeof(lr->saveDir) - strlen(lr->saveDir) - 1);
        mkdir(lr->saveDir, 0755);
    } else {
        lr->saveDir[0] = 0;
    }
    current = lr;

    // Same order as RetroArch: environment, init, then the other callbacks.
    api->set_environment(environment_cb);
    if (!core->initialized) {
        api->init();
        core->initialized = true;
    }
    api->set_video_refresh(video_cb);
    api->set_audio_sample(audio_sample_cb);
    api->set_audio_sample_batch(audio_batch_cb);
    api->set_input_poll(input_poll_cb);
    api->set_input_state(input_state_cb);

    // Some cores read the file themselves (need_fullpath); others want it loaded into memory.
    struct retro_system_info sys;
    memset(&sys, 0, sizeof(sys));
    api->get_system_info(&sys);
    void* data = NULL;
    size_t dataSize = 0;
    if (!sys.need_fullpath) {
        FILE* f = fopen(contentPath, "rb");
        if (f) {
            fseek(f, 0, SEEK_END);
            long n = ftell(f);
            fseek(f, 0, SEEK_SET);
            if (n > 0 && n < 256 * 1024 * 1024) {
                data = malloc((size_t) n);
                dataSize = fread(data, 1, (size_t) n, f);
            }
            fclose(f);
        }
    }
    lr->contentData = data;
    struct retro_game_info info = { .path = contentPath, .data = data, .size = dataSize, .meta = NULL };
    if (!api->load_game(&info)) {
        e4lr_debug("retro_load_game failed for %s\n", contentPath);
        free(data);
        current = NULL;
        free(lr);
        return NULL;
    }
    lr->loaded = true;
    api->set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    api->get_system_av_info(&lr->av);
#ifdef __APPLE__
    if (lr->usesHW) {
        unsigned mw = lr->av.geometry.max_width ? lr->av.geometry.max_width : 1024;
        unsigned mh = lr->av.geometry.max_height ? lr->av.geometry.max_height : 1024;
        bool gles3 = lr->hw.context_type != RETRO_HW_CONTEXT_OPENGLES2;
        lr->gl = e4gl_create(gles3, mw, mh, lr->hw.depth, lr->hw.stencil);
        if (!lr->gl) {
            api->unload_game();
            current = NULL;
            free(lr->contentData);
            free(lr);
            return NULL;
        }
        if (lr->hw.context_reset) lr->hw.context_reset();
        e4gl_release_current(); // the emulation thread makes it current before each frame
    }
#endif
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
    enter(lr);
#ifdef __APPLE__
    if (lr->gl && lr->hw.context_destroy) lr->hw.context_destroy();
#endif
    if (lr->loaded) api->unload_game();
#ifdef __APPLE__
    if (lr->gl) e4gl_destroy(lr->gl);
#endif
    free(lr->memoryMap);
    // Keep the core initialized between games (some cores don't like deinit/init cycles).
    if (current == lr) current = NULL;
    free(lr->video);
    free(lr->audio);
    free(lr->contentData);
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
    if (!api) { if (outSize) out[0] = 0; return; }
    api->get_system_info(&info);
    snprintf(out, outSize, "%s %s", info.library_name ? info.library_name : "", info.library_version ? info.library_version : "");
}

// MARK: - Running

void e4lr_set_buttons(E4Libretro* lr, uint32_t mask) { lr->buttons = mask; lr->portButtons[0] = mask; }
void e4lr_set_port_buttons(E4Libretro* lr, unsigned port, uint32_t mask) { if (port < 4) lr->portButtons[port] = mask; }
void e4lr_set_analog(E4Libretro* lr, unsigned port, unsigned stick, int16_t x, int16_t y) {
    if (port < 4 && stick < 2) { lr->analog[port][stick][0] = x; lr->analog[port][stick][1] = y; }
}
void e4lr_set_pointer(E4Libretro* lr, int16_t x, int16_t y, bool pressed) {
    lr->pointerX = x; lr->pointerY = y; lr->pointerPressed = pressed;
}
void e4lr_mouse(E4Libretro* lr, int16_t dx, int16_t dy, bool left, bool right) {
    lr->mouseDX += dx; lr->mouseDY += dy; lr->mouseLeft = left; lr->mouseRight = right;
}
void e4lr_key(E4Libretro* lr, unsigned keycode, bool down, uint32_t character, uint16_t modifiers) {
    if (keycode < RETROK_LAST) lr->keys[keycode] = down;
    if (lr->keyboardCallback) lr->keyboardCallback(down, keycode, character, modifiers);
}
bool e4lr_uses_gpu(const E4Libretro* lr) { return lr->usesHW; }

/// Reads emulated memory through the core's memory map (used by RetroAchievements).
size_t e4lr_memory_map_count(const E4Libretro* lr) { return lr->memoryMapCount; }
const void* e4lr_memory_map(const E4Libretro* lr) { return lr->memoryMap; }
uint8_t* e4lr_memory(unsigned id, size_t* size) {
    if (!api) { if (size) *size = 0; return NULL; }
    if (size) *size = api->get_memory_size(id);
    return api->get_memory_data(id);
}

/// Every call into the core goes through here: callbacks need `current`, GPU cores need their GL context.
static void enter(E4Libretro* lr) {
    current = lr;
#ifdef __APPLE__
    if (lr && lr->gl) e4gl_make_current(lr->gl);
#endif
}

/// After a call made from another thread (save states, cheats…), let go of the GL context so only
/// one thread ever has it current.
static void leave(E4Libretro* lr) {
#ifdef __APPLE__
    if (lr && lr->gl) e4gl_release_current();
#else
    (void) lr;
#endif
}

void e4lr_run_frame(E4Libretro* lr) {
    enter(lr);
    api->run();
}

void e4lr_reset(E4Libretro* lr) { enter(lr); api->reset(); leave(lr); }

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

size_t e4lr_state_size(E4Libretro* lr) { enter(lr); size_t n = api->serialize_size(); leave(lr); return n; }

bool e4lr_save_state(E4Libretro* lr, void* buffer, size_t size) {
    enter(lr);
    bool ok = api->serialize(buffer, size);
    leave(lr);
    return ok;
}

bool e4lr_load_state(E4Libretro* lr, const void* buffer, size_t size) {
    enter(lr);
    bool ok = api->unserialize(buffer, size);
    leave(lr);
    return ok;
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
    enter(lr);
    char* joined = strdup(code);
    for (char* p = joined; *p; p++) if (*p == '\n' || *p == '\r') *p = '+';
    api->cheat_set(lr->cheatIndex++, true, joined);
    free(joined);
    return true;
}

void e4lr_clear_cheats(E4Libretro* lr) {
    enter(lr);
    api->cheat_reset();
    lr->cheatIndex = 0;
}
