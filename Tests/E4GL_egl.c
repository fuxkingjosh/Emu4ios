// Linux stand-in for App/Bridge/E4GL.m, so GPU cores (PSP, N64) can be tested with the app's real
// bridge code on a machine without a screen. Uses Mesa through EGL's surfaceless platform.
// E4_GLES2=1 forces an ES 2 context (what older Emu4ios builds created) for comparison.
#define _GNU_SOURCE
#include "E4GL.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct E4GL {
    EGLDisplay display;
    EGLContext context;
    GLuint fbo, color, depth;
    unsigned width, height;
    uint8_t* scratch;
};

E4GL* e4gl_create(bool gles3, unsigned maxWidth, unsigned maxHeight, bool depth, bool stencil) {
    if (getenv("E4_GLES2")) gles3 = false;
    PFNEGLGETPLATFORMDISPLAYEXTPROC getDisplay = (PFNEGLGETPLATFORMDISPLAYEXTPROC) eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay dpy = getDisplay ? getDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL) : EGL_NO_DISPLAY;
    if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) { fprintf(stderr, "EGL init failed\n"); return NULL; }
    eglBindAPI(EGL_OPENGL_ES_API);
    EGLint cfgAttrs[] = { EGL_SURFACE_TYPE, EGL_DONT_CARE, EGL_RENDERABLE_TYPE, gles3 ? EGL_OPENGL_ES3_BIT : EGL_OPENGL_ES2_BIT, EGL_NONE };
    EGLConfig cfg; EGLint n = 0;
    if (!eglChooseConfig(dpy, cfgAttrs, &cfg, 1, &n) || n == 0) { fprintf(stderr, "no EGL config\n"); return NULL; }
    EGLint ctxAttrs[] = { EGL_CONTEXT_MAJOR_VERSION, gles3 ? 3 : 2, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxAttrs);
    if (ctx == EGL_NO_CONTEXT) { fprintf(stderr, "no EGL context\n"); return NULL; }
    E4GL* gl = calloc(1, sizeof(*gl));
    gl->display = dpy; gl->context = ctx;
    gl->width = maxWidth ? maxWidth : 1024;
    gl->height = maxHeight ? maxHeight : 1024;
    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx);
    fprintf(stderr, "[E4GL] %s\n", glGetString(GL_VERSION));
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
    eglMakeCurrent(gl->display, EGL_NO_SURFACE, EGL_NO_SURFACE, gl->context);
    if (gl->depth) glDeleteRenderbuffers(1, &gl->depth);
    glDeleteRenderbuffers(1, &gl->color);
    glDeleteFramebuffers(1, &gl->fbo);
    eglMakeCurrent(gl->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(gl->display, gl->context);
    free(gl->scratch);
    free(gl);
}

void e4gl_make_current(E4GL* gl) {
    if (gl && eglGetCurrentContext() != gl->context) eglMakeCurrent(gl->display, EGL_NO_SURFACE, EGL_NO_SURFACE, gl->context);
}

void e4gl_release_current(void) {
    EGLDisplay d = eglGetCurrentDisplay();
    if (d != EGL_NO_DISPLAY) eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
}

unsigned e4gl_framebuffer(E4GL* gl) { return gl ? gl->fbo : 0; }

void* e4gl_proc_address(const char* name) { return (void*) eglGetProcAddress(name); }

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
}
