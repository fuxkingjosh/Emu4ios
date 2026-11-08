// Runs any libretro core through Emu4ios's bridge for a few seconds and dumps the last frame.
// usage: core_test <core.so/.dylib> <content> <out.ppm> [frames] [buttons]
#include "E4Libretro.h"
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    if (argc < 4) { fprintf(stderr, "usage\n"); return 2; }
    int frames = argc > 4 ? atoi(argv[4]) : 120;
    unsigned buttons = argc > 5 ? (unsigned) strtoul(argv[5], 0, 0) : 0;
    E4Libretro* lr = e4lr_create(argv[1], argv[2], "/tmp/core_test.srm", "/tmp");
    if (!lr) { puts("LOAD FAILED"); return 1; }
    char name[96]; e4lr_core_name(name, sizeof name);
    int16_t audio[16384]; size_t total = 0;
    for (int i = 0; i < frames; i++) {
        e4lr_set_buttons(lr, (i / 20) % 2 ? buttons : 0);
        e4lr_run_frame(lr);
        total += e4lr_read_audio(lr, audio, 8192);
    }
    unsigned w, h; const uint32_t* p = e4lr_pixels(lr, &w, &h);
    size_t ss = e4lr_state_size(lr); void* st = malloc(ss ? ss : 1);
    int saved = ss ? e4lr_save_state(lr, st, ss) : 0;
    int loaded = saved ? e4lr_load_state(lr, st, ss) : 0;
    unsigned long distinct = 0; uint32_t last = 0xFFFFFFFF;
    for (unsigned i = 0; i < w * h; i += 97) if (p[i] != last) { distinct++; last = p[i]; }
    printf("core=%s video=%ux%u fps=%.2f rate=%.0f aspect=%.3f audioFrames=%zu state=%zu save=%d load=%d colorChanges=%lu center=%06x\n",
           name, w, h, e4lr_fps(lr), e4lr_sample_rate(lr), e4lr_aspect_ratio(lr), total, ss, saved, loaded, distinct, (w && h) ? (p[(h / 2) * w + w / 2] & 0xFFFFFF) : 0);
    FILE* f = fopen(argv[3], "wb");
    fprintf(f, "P6 %u %u 255\n", w, h);
    for (unsigned i = 0; i < w * h; i++) { uint32_t px = p[i]; fputc(px & 0xFF, f); fputc((px >> 8) & 0xFF, f); fputc((px >> 16) & 0xFF, f); }
    fclose(f);
    e4lr_destroy(lr);
    // Second load in the same process (switching games) must work too.
    E4Libretro* again = e4lr_create(argv[1], argv[2], "/tmp/core_test.srm", "/tmp");
    printf("reload=%s\n", again ? "ok" : "FAILED");
    if (again) { for (int i = 0; i < 10; i++) e4lr_run_frame(again); e4lr_destroy(again); }
    return 0;
}
