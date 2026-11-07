#include "E4Emulator.h"

#include "mgba-defines.h"
#include <mgba/flags.h>

#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba/core/cheats.h>
#include <mgba/core/config.h>
#include <mgba/core/serialize.h>
#include <mgba-util/audio-buffer.h>
#include <mgba-util/vfs.h>

#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define E4_MAX_WIDTH 256
#define E4_MAX_HEIGHT 224

struct E4Emulator {
    struct mCore* core;
    mColor* video;
    E4System system;
    bool hasCheatSet;
};

static void quietLog(struct mLogger* logger, int category, enum mLogLevel level, const char* format, va_list args) {
    (void) logger; (void) category; (void) level; (void) format; (void) args;
}
static struct mLogger quietLogger = { .log = quietLog, .filter = NULL };

static E4System detectSystem(struct mCore* core, const char* romPath) {
    if (core->platform(core) == mPLATFORM_GBA) {
        return E4SystemGBA;
    }
    // Game Boy family: byte 0x143 of the header marks Color support.
    E4System system = E4SystemGB;
    FILE* f = fopen(romPath, "rb");
    if (f) {
        if (fseek(f, 0x143, SEEK_SET) == 0) {
            int flag = fgetc(f);
            if (flag == 0x80 || flag == 0xC0) {
                system = E4SystemGBC;
            }
        }
        fclose(f);
    }
    return system;
}

E4Emulator* e4_create(const char* romPath, const char* savePath) {
    mLogSetDefaultLogger(&quietLogger);
    struct VFile* rom = VFileOpen(romPath, O_RDONLY);
    if (!rom) {
        return NULL;
    }
    // Only accept systems we actually support (avoids mGBA's video-log fallback).
    enum mPlatform platform = mCoreIsCompatible(rom);
    struct mCore* core = platform == mPLATFORM_NONE ? NULL : mCoreCreate(platform);
    if (!core) {
        rom->close(rom);
        return NULL;
    }

    E4Emulator* emu = calloc(1, sizeof(*emu));
    emu->core = core;

    mCoreInitConfig(core, NULL);
    core->init(core);

    // Sensible defaults: skip idle loops for battery life, allow BIOS-less boot.
    mCoreConfigSetDefaultValue(&core->config, "idleOptimization", "detect");
    mCoreConfigSetDefaultIntValue(&core->config, "useBios", 0);
    mCoreConfigSetDefaultIntValue(&core->config, "skipBios", 1);
    mCoreLoadConfig(core);

    emu->video = calloc(E4_MAX_WIDTH * E4_MAX_HEIGHT, sizeof(mColor));
    core->setVideoBuffer(core, emu->video, E4_MAX_WIDTH);
    core->setAudioBufferSize(core, 4096);

    if (!core->loadROM(core, rom)) {
        e4_destroy(emu);
        return NULL;
    }

    if (savePath && savePath[0]) {
        struct VFile* save = VFileOpen(savePath, O_CREAT | O_RDWR);
        if (save) {
            core->loadSave(core, save);
        }
    }

    core->reset(core);
    emu->system = detectSystem(core, romPath);
    return emu;
}

void e4_destroy(E4Emulator* emu) {
    if (!emu) {
        return;
    }
    if (emu->core) {
        emu->core->unloadROM(emu->core);
        mCoreConfigDeinit(&emu->core->config);
        emu->core->deinit(emu->core);
    }
    free(emu->video);
    free(emu);
}

E4System e4_system(const E4Emulator* emu) {
    return emu ? emu->system : E4SystemUnknown;
}

void e4_video_size(const E4Emulator* emu, unsigned* width, unsigned* height) {
    emu->core->currentVideoSize(emu->core, width, height);
}

double e4_fps(const E4Emulator* emu) {
    return (double) emu->core->frequency(emu->core) / (double) emu->core->frameCycles(emu->core);
}

unsigned e4_sample_rate(const E4Emulator* emu) {
    return emu->core->audioSampleRate(emu->core);
}

void e4_title(const E4Emulator* emu, char* out, size_t outSize) {
    if (!out || outSize == 0) {
        return;
    }
    struct mGameInfo info;
    memset(&info, 0, sizeof(info));
    emu->core->getGameInfo(emu->core, &info);
    snprintf(out, outSize, "%s", info.title);
}

void e4_set_buttons(E4Emulator* emu, uint32_t buttons) {
    // E4Button bits match mGBA's GBA key order, which the GB core shares.
    emu->core->setKeys(emu->core, buttons & 0x3FF);
}

void e4_run_frame(E4Emulator* emu) {
    emu->core->runFrame(emu->core);
}

void e4_reset(E4Emulator* emu) {
    emu->core->reset(emu->core);
}

const uint32_t* e4_pixels(const E4Emulator* emu, size_t* stride) {
    if (stride) {
        *stride = E4_MAX_WIDTH;
    }
    return (const uint32_t*) emu->video;
}

size_t e4_read_audio(E4Emulator* emu, int16_t* out, size_t maxFrames) {
    struct mAudioBuffer* buffer = emu->core->getAudioBuffer(emu->core);
    if (!buffer) {
        return 0;
    }
    size_t available = mAudioBufferAvailable(buffer);
    if (available > maxFrames) {
        available = maxFrames;
    }
    return mAudioBufferRead(buffer, out, available);
}

size_t e4_state_size(E4Emulator* emu) {
    struct VFile* vf = VFileMemChunk(NULL, 0);
    mCoreSaveStateNamed(emu->core, vf, SAVESTATE_SAVEDATA | SAVESTATE_RTC);
    size_t size = (size_t) vf->size(vf);
    vf->close(vf);
    return size;
}

bool e4_save_state(E4Emulator* emu, void* buffer, size_t size, size_t* written, bool withSaveData) {
    struct VFile* vf = VFileMemChunk(NULL, 0);
    int flags = SAVESTATE_RTC | (withSaveData ? SAVESTATE_SAVEDATA : 0);
    if (!mCoreSaveStateNamed(emu->core, vf, flags)) {
        vf->close(vf);
        return false;
    }
    size_t actual = (size_t) vf->size(vf);
    if (actual > size) {
        vf->close(vf);
        return false;
    }
    vf->seek(vf, 0, SEEK_SET);
    vf->read(vf, buffer, actual);
    vf->close(vf);
    if (written) {
        *written = actual;
    }
    return true;
}

bool e4_load_state(E4Emulator* emu, const void* buffer, size_t size) {
    struct VFile* vf = VFileFromConstMemory(buffer, size);
    bool ok = mCoreLoadStateNamed(emu->core, vf, SAVESTATE_RTC);
    vf->close(vf);
    return ok;
}

bool e4_save_state_file(E4Emulator* emu, const char* path) {
    struct VFile* vf = VFileOpen(path, O_CREAT | O_TRUNC | O_RDWR);
    if (!vf) {
        return false;
    }
    bool ok = mCoreSaveStateNamed(emu->core, vf, SAVESTATE_SAVEDATA | SAVESTATE_RTC);
    vf->close(vf);
    return ok;
}

bool e4_load_state_file(E4Emulator* emu, const char* path) {
    struct VFile* vf = VFileOpen(path, O_RDONLY);
    if (!vf) {
        return false;
    }
    bool ok = mCoreLoadStateNamed(emu->core, vf, SAVESTATE_RTC);
    vf->close(vf);
    return ok;
}

bool e4_add_cheat(E4Emulator* emu, const char* name, const char* code) {
    struct mCheatDevice* device = emu->core->cheatDevice(emu->core);
    if (!device) {
        return false;
    }
    struct mCheatSet* set = device->createSet(device, name);
    // Codes may be pasted one per line.
    bool any = false;
    char* copy = strdup(code);
    char* save = NULL;
    for (char* line = strtok_r(copy, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        while (*line == ' ' || *line == '\t' || *line == '\r') {
            ++line;
        }
        if (*line && mCheatAddLine(set, line, 0)) {
            any = true;
        }
    }
    free(copy);
    if (!any) {
        mCheatSetDeinit(set);
        return false;
    }
    set->enabled = true;
    mCheatAddSet(device, set);
    emu->hasCheatSet = true;
    return true;
}

void e4_clear_cheats(E4Emulator* emu) {
    struct mCheatDevice* device = emu->core->cheatDevice(emu->core);
    if (device) {
        mCheatDeviceClear(device);
    }
    emu->hasCheatSet = false;
}

uint8_t e4_peek(E4Emulator* emu, uint32_t address) {
    return (uint8_t) emu->core->busRead8(emu->core, address);
}
