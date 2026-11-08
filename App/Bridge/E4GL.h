// E4GL — an offscreen OpenGL ES context for libretro cores that draw with the GPU
// (Nintendo 64, PSP). Frames are read back and shown through the normal Metal pipeline.
#ifndef E4_GL_H
#define E4_GL_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct E4GL E4GL;

/// `gles3`: request OpenGL ES 3 (falls back to 2). Creates a framebuffer of maxWidth × maxHeight.
E4GL* e4gl_create(bool gles3, unsigned maxWidth, unsigned maxHeight, bool depth, bool stencil);
void e4gl_destroy(E4GL* gl);
/// Makes the context current on the calling thread.
void e4gl_make_current(E4GL* gl);
/// Clears the calling thread's current context (so only the emulation thread holds it).
void e4gl_release_current(void);
unsigned e4gl_framebuffer(E4GL* gl);
void* e4gl_proc_address(const char* name);
/// Reads a width × height frame into `out` as RGBX, top row first.
void e4gl_read(E4GL* gl, unsigned width, unsigned height, bool bottomLeftOrigin, uint32_t* out);

#ifdef __cplusplus
}
#endif

#endif
