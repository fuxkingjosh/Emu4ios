#define GLES_SILENCE_DEPRECATION 1
#import "E4GL.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

struct E4GL {
    EAGLContext* context;
    GLuint fbo, color, depth;
    unsigned width, height;
    uint8_t* scratch;
};

E4GL* e4gl_create(bool gles3, unsigned maxWidth, unsigned maxHeight, bool depth, bool stencil) {
    EAGLContext* ctx = nil;
    if (gles3) ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!ctx) ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!ctx) return NULL;
    E4GL* gl = calloc(1, sizeof(*gl));
    gl->context = ctx;
    gl->width = maxWidth ? maxWidth : 1024;
    gl->height = maxHeight ? maxHeight : 1024;
    [EAGLContext setCurrentContext:ctx];

    glGenFramebuffers(1, &gl->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, gl->fbo);
    glGenRenderbuffers(1, &gl->color);
    glBindRenderbuffer(GL_RENDERBUFFER, gl->color);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, gl->width, gl->height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, gl->color);
    if (depth || stencil) {
        glGenRenderbuffers(1, &gl->depth);
        glBindRenderbuffer(GL_RENDERBUFFER, gl->depth);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, gl->width, gl->height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, gl->depth);
        if (stencil) glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, gl->depth);
    }
    glViewport(0, 0, gl->width, gl->height);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    gl->scratch = malloc((size_t) gl->width * gl->height * 4);
    return gl;
}

void e4gl_destroy(E4GL* gl) {
    if (!gl) return;
    [EAGLContext setCurrentContext:gl->context];
    if (gl->depth) glDeleteRenderbuffers(1, &gl->depth);
    glDeleteRenderbuffers(1, &gl->color);
    glDeleteFramebuffers(1, &gl->fbo);
    [EAGLContext setCurrentContext:nil];
    gl->context = nil;
    free(gl->scratch);
    free(gl);
}

void e4gl_make_current(E4GL* gl) {
    if (gl && [EAGLContext currentContext] != gl->context) [EAGLContext setCurrentContext:gl->context];
}

void e4gl_release_current(void) { [EAGLContext setCurrentContext:nil]; }

unsigned e4gl_framebuffer(E4GL* gl) { return gl ? gl->fbo : 0; }

void* e4gl_proc_address(const char* name) {
    return dlsym(RTLD_DEFAULT, name);
}

void e4gl_read(E4GL* gl, unsigned width, unsigned height, bool bottomLeftOrigin, uint32_t* out) {
    if (!gl || !out || width == 0 || height == 0) return;
    if (width > gl->width) width = gl->width;
    if (height > gl->height) height = gl->height;
    glBindFramebuffer(GL_FRAMEBUFFER, gl->fbo);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(0, 0, (GLsizei) width, (GLsizei) height, GL_RGBA, GL_UNSIGNED_BYTE, gl->scratch);
    size_t row = (size_t) width * 4;
    for (unsigned y = 0; y < height; y++) {
        unsigned srcY = bottomLeftOrigin ? (height - 1 - y) : y;
        memcpy((uint8_t*) out + y * row, gl->scratch + srcY * row, row);
    }
    // Alpha is unused by the renderer (RGBX), so no need to touch it.
}
