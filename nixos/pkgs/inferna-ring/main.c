#define _POSIX_C_SOURCE 200809L
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#ifndef DEFAULT_SHADER_PATH
#define DEFAULT_SHADER_PATH "ring.frag"
#endif

static volatile sig_atomic_t g_stop = 0;

static void handle_sig(int sig) {
    (void)sig;
    g_stop = 1;
}

static char *read_entire_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf);
        fclose(f);
        return NULL;
    }
    buf[sz] = '\0';
    fclose(f);
    return buf;
}

static GLuint compile_shader(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[2048];
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        fprintf(stderr, "inferna-ring: shader compile error:\n%s\n", log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

// Fast base64 encoder for Kitty Graphics Protocol
static size_t base64_encode(const uint8_t *in, size_t len, char *out) {
    static const char tbl[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t i = 0, j = 0;
    while (i + 3 <= len) {
        uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8) | in[i + 2];
        out[j++] = tbl[(v >> 18) & 63];
        out[j++] = tbl[(v >> 12) & 63];
        out[j++] = tbl[(v >> 6) & 63];
        out[j++] = tbl[v & 63];
        i += 3;
    }
    if (i < len) {
        uint32_t v = (uint32_t)in[i] << 16;
        if (i + 1 < len) v |= (uint32_t)in[i + 1] << 8;
        out[j++] = tbl[(v >> 18) & 63];
        out[j++] = tbl[(v >> 12) & 63];
        out[j++] = (i + 1 < len) ? tbl[(v >> 6) & 63] : '=';
        out[j++] = '=';
    }
    return j;
}

// Flip OpenGL bottom-up RGBA into top-down RGBA
static void flip_rgba_vertical(const uint8_t *src, uint8_t *dst, int w, int h) {
    size_t row_bytes = (size_t)w * 4;
    for (int y = 0; y < h; y++) {
        memcpy(dst + (size_t)y * row_bytes, src + (size_t)(h - 1 - y) * row_bytes, row_bytes);
    }
}

// Transmit full-resolution RGBA image via Kitty Graphics Protocol (Ghostty / Kitty / WezTerm)
static void render_kitty(const uint8_t *gl_rgba, uint8_t *topdown, char *b64_buf,
                         int w, int h, int cols, int rows, bool keep_cursor, uint32_t img_id) {
    flip_rgba_vertical(gl_rgba, topdown, w, h);
    size_t raw_len = (size_t)w * (size_t)h * 4;
    size_t b64_len = base64_encode(topdown, raw_len, b64_buf);

    const size_t chunk_sz = 4096;
    size_t off = 0;
    bool first = true;

    fputs("\x1b[?2026h", stdout);
    while (off < b64_len) {
        size_t n = b64_len - off;
        if (n > chunk_sz) n = chunk_sz;
        int more = (off + n < b64_len) ? 1 : 0;

        if (first) {
            if (cols > 0 && rows > 0) {
                fprintf(stdout, "\x1b_Ga=T,f=32,s=%d,v=%d,c=%d,r=%d,i=%u,p=1,q=2,C=%d,m=%d;",
                        w, h, cols, rows, img_id, keep_cursor ? 1 : 0, more);
            } else {
                fprintf(stdout, "\x1b_Ga=T,f=32,s=%d,v=%d,i=%u,p=1,q=2,C=%d,m=%d;",
                        w, h, img_id, keep_cursor ? 1 : 0, more);
            }
            first = false;
        } else {
            fprintf(stdout, "\x1b_Gm=%d;", more);
        }
        fwrite(b64_buf + off, 1, n, stdout);
        fputs("\x1b\\", stdout);
        off += n;
    }
    fputs("\x1b[?2026l", stdout);
    fflush(stdout);
}

static void render_halfblocks(const uint8_t *rgba, int w, int h, bool home_cursor) {
    size_t cap = (size_t)(w * (h / 2) * 44 + 512);
    char *out = malloc(cap);
    if (!out) return;
    size_t pos = 0;

    if (home_cursor) {
        pos += (size_t)snprintf(out + pos, cap - pos, "\x1b[?2026h\x1b[H");
    }

    int rows = h / 2;
    for (int row = 0; row < rows; row++) {
        int y_top = h - 1 - (row * 2);
        int y_bot = h - 1 - (row * 2 + 1);
        int prev_fr = -1, prev_fg = -1, prev_fb = -1;
        int prev_br = -1, prev_bg = -1, prev_bb = -1;

        for (int x = 0; x < w; x++) {
            const uint8_t *pt = &rgba[(y_top * w + x) * 4];
            const uint8_t *pb = &rgba[(y_bot * w + x) * 4];
            // Composite over Inferna #100C0A (16, 12, 10)
            float at = pt[3] / 255.0f;
            float ab = pb[3] / 255.0f;
            int fr = (int)(pt[0] * at + 16.0f * (1.0f - at));
            int fg = (int)(pt[1] * at + 12.0f * (1.0f - at));
            int fb = (int)(pt[2] * at + 10.0f * (1.0f - at));
            int br = (int)(pb[0] * ab + 16.0f * (1.0f - ab));
            int bg = (int)(pb[1] * ab + 12.0f * (1.0f - ab));
            int bb = (int)(pb[2] * ab + 10.0f * (1.0f - ab));

            if (fr != prev_fr || fg != prev_fg || fb != prev_fb) {
                pos += (size_t)snprintf(out + pos, cap - pos, "\x1b[38;2;%d;%d;%dm", fr, fg, fb);
                prev_fr = fr; prev_fg = fg; prev_fb = fb;
            }
            if (br != prev_br || bg != prev_bg || bb != prev_bb) {
                pos += (size_t)snprintf(out + pos, cap - pos, "\x1b[48;2;%d;%d;%dm", br, bg, bb);
                prev_br = br; prev_bg = bg; prev_bb = bb;
            }
            memcpy(out + pos, "\xe2\x96\x80", 3);
            pos += 3;
        }
        memcpy(out + pos, "\x1b[0m\n", 5);
        pos += 5;
    }

    if (home_cursor) {
        pos += (size_t)snprintf(out + pos, cap - pos, "\x1b[?2026l");
    }

    fwrite(out, 1, pos, stdout);
    fflush(stdout);
    free(out);
}

static bool write_ppm(const char *path, const uint8_t *rgba, int w, int h) {
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int y = h - 1; y >= 0; y--) {
        for (int x = 0; x < w; x++) {
            const uint8_t *p = &rgba[(y * w + x) * 4];
            float a = p[3] / 255.0f;
            uint8_t rgb[3] = {
                (uint8_t)(p[0] * a + 16.0f * (1.0f - a)),
                (uint8_t)(p[1] * a + 12.0f * (1.0f - a)),
                (uint8_t)(p[2] * a + 10.0f * (1.0f - a)),
            };
            fwrite(rgb, 1, 3, f);
        }
    }
    fclose(f);
    return true;
}

static EGLDisplay create_headless_display(void) {
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    if (get_platform_display) {
        EGLDisplay dpy = get_platform_display(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
        if (dpy != EGL_NO_DISPLAY) return dpy;
    }
    return eglGetDisplay(EGL_DEFAULT_DISPLAY);
}

static bool key_pressed(void) {
    struct pollfd pfd = { .fd = STDIN_FILENO, .events = POLLIN };
    if (poll(&pfd, 1, 0) > 0 && (pfd.revents & POLLIN)) {
        char buf[32];
        ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
        (void)n;
        return true;
    }
    return false;
}

static void usage(const char *argv0) {
    fprintf(stderr,
        "Usage: %s [options]\n"
        "  --kitty            High-resolution pixel output via Kitty Graphics Protocol (Ghostty/Kitty)\n"
        "  --size <px>        Pixel resolution for --kitty or --ppm (default: 320)\n"
        "  --cols <n>         Display width in terminal columns (default: 26 for --kitty, 36 halfblock)\n"
        "  --rows <n>         Display height in terminal rows (default: 13 for --kitty, 18 halfblock)\n"
        "  --yaw <deg>        Initial 3D yaw angle in degrees (default: 20)\n"
        "  --pitch <deg>      Initial 3D pitch angle in degrees (default: -14)\n"
        "  --time <sec>       Shader timestamp (default: 0.0)\n"
        "  --animate          Spin the 3D GLSL ring live (press any key or Ctrl+C to continue)\n"
        "  --duration <sec>   Optional auto-stop duration in seconds when animating (0 = infinite)\n"
        "  --fps <n>          Animation framerate (default: 30)\n"
        "  --inline           Animate inline in scrollback instead of alternate screen\n"
        "  --ppm <file>       Render to a PPM image file\n"
        "  --shader <path>    Custom GLSL fragment shader path\n",
        argv0);
}

int main(int argc, char **argv) {
    bool use_kitty = false;
    int size_px = 320;
    int cols = 0;
    int rows = 0;
    float yaw_deg = 20.0f;
    float pitch_deg = -14.0f;
    float t_sec = 0.0f;
    bool animate = false;
    bool inline_anim = false;
    float duration = 0.0f;
    int fps = 30;
    const char *ppm_path = NULL;
    const char *shader_path = DEFAULT_SHADER_PATH;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--kitty")) use_kitty = true;
        else if (!strcmp(argv[i], "--size") && i + 1 < argc) size_px = atoi(argv[++i]);
        else if ((!strcmp(argv[i], "--cols") || !strcmp(argv[i], "--width")) && i + 1 < argc) cols = atoi(argv[++i]);
        else if ((!strcmp(argv[i], "--rows") || !strcmp(argv[i], "--height")) && i + 1 < argc) rows = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--yaw") && i + 1 < argc) yaw_deg = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--pitch") && i + 1 < argc) pitch_deg = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--time") && i + 1 < argc) t_sec = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--animate")) animate = true;
        else if (!strcmp(argv[i], "--inline")) inline_anim = true;
        else if (!strcmp(argv[i], "--duration") && i + 1 < argc) duration = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--fps") && i + 1 < argc) fps = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--ppm") && i + 1 < argc) ppm_path = argv[++i];
        else if (!strcmp(argv[i], "--shader") && i + 1 < argc) shader_path = argv[++i];
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(argv[0]); return 0; }
        else { fprintf(stderr, "Unknown option: %s\n", argv[i]); usage(argv[0]); return 1; }
    }

    if (cols <= 0) cols = use_kitty ? 28 : 36;
    if (rows <= 0) rows = use_kitty ? 14 : 18;
    if (size_px < 64) size_px = 64;
    if (size_px > 1024) size_px = 1024;
    if (fps < 1) fps = 1;
    if (fps > 60) fps = 60;

    int px_w = (use_kitty || ppm_path) ? size_px : cols;
    int px_h = (use_kitty || ppm_path) ? size_px : rows * 2;

    char *frag_src = read_entire_file(shader_path);
    if (!frag_src) {
        fprintf(stderr, "inferna-ring: cannot read shader '%s'\n", shader_path);
        return 1;
    }

    EGLDisplay dpy = create_headless_display();
    if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) {
        fprintf(stderr, "inferna-ring: eglInitialize failed\n");
        free(frag_src);
        return 1;
    }

    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        fprintf(stderr, "inferna-ring: eglBindAPI(GLES) failed\n");
        eglTerminate(dpy);
        free(frag_src);
        return 1;
    }

    const EGLint cfg_attribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLConfig cfg;
    EGLint num_cfg = 0;
    if (!eglChooseConfig(dpy, cfg_attribs, &cfg, 1, &num_cfg) || num_cfg < 1) {
        const EGLint sl_attribs[] = {
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
            EGL_NONE
        };
        if (!eglChooseConfig(dpy, sl_attribs, &cfg, 1, &num_cfg) || num_cfg < 1) {
            fprintf(stderr, "inferna-ring: eglChooseConfig failed\n");
            eglTerminate(dpy);
            free(frag_src);
            return 1;
        }
    }

    const EGLint ctx_attribs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attribs);
    if (ctx == EGL_NO_CONTEXT) {
        fprintf(stderr, "inferna-ring: eglCreateContext failed\n");
        eglTerminate(dpy);
        free(frag_src);
        return 1;
    }

    EGLSurface surf = EGL_NO_SURFACE;
    if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
        const EGLint pb_attribs[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
        surf = eglCreatePbufferSurface(dpy, cfg, pb_attribs);
        if (surf == EGL_NO_SURFACE || !eglMakeCurrent(dpy, surf, surf, ctx)) {
            fprintf(stderr, "inferna-ring: eglMakeCurrent failed\n");
            eglDestroyContext(dpy, ctx);
            eglTerminate(dpy);
            free(frag_src);
            return 1;
        }
    }

    GLuint fbo = 0, tex = 0;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, px_w, px_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);

    static const char *vert_src =
        "#version 300 es\n"
        "void main() {\n"
        "  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);\n"
        "  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n"
        "}\n";

    GLuint vs = compile_shader(GL_VERTEX_SHADER, vert_src);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, frag_src);
    free(frag_src);
    if (!vs || !fs) return 1;

    GLuint prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glLinkProgram(prog);
    GLint linked = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[1024];
        glGetProgramInfoLog(prog, sizeof(log), NULL, log);
        fprintf(stderr, "inferna-ring: link error:\n%s\n", log);
        return 1;
    }

    GLuint vao = 0;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glUseProgram(prog);
    glViewport(0, 0, px_w, px_h);

    GLint loc_res   = glGetUniformLocation(prog, "u_res");
    GLint loc_time  = glGetUniformLocation(prog, "u_time");
    GLint loc_yaw   = glGetUniformLocation(prog, "u_yaw");
    GLint loc_pitch = glGetUniformLocation(prog, "u_pitch");

    size_t rgba_sz = (size_t)px_w * (size_t)px_h * 4;
    uint8_t *pixels = malloc(rgba_sz);
    uint8_t *topdown = use_kitty ? malloc(rgba_sz) : NULL;
    char *b64_buf = use_kitty ? malloc(((rgba_sz + 2) / 3) * 4 + 16) : NULL;
    if (!pixels || (use_kitty && (!topdown || !b64_buf))) return 1;

    const float deg2rad = 3.14159265359f / 180.0f;

    if (animate) {
        signal(SIGINT, handle_sig);
        signal(SIGTERM, handle_sig);

        bool tty_stdin = isatty(STDIN_FILENO);
        struct termios orig_term;
        if (tty_stdin && tcgetattr(STDIN_FILENO, &orig_term) == 0) {
            struct termios raw = orig_term;
            raw.c_lflag &= (tcflag_t)~(ICANON | ECHO);
            raw.c_cc[VMIN] = 0;
            raw.c_cc[VTIME] = 0;
            tcsetattr(STDIN_FILENO, TCSANOW, &raw);
        } else {
            tty_stdin = false;
        }

        if (inline_anim) {
            // Reserve space inline so the spinning ring sits cleanly above the prompt
            for (int r = 0; r < rows; r++) fputc('\n', stdout);
            fprintf(stdout, "\x1b[%dA\x1b[?25l", rows);
        } else {
            fputs("\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H", stdout);
        }
        fflush(stdout);

        struct timespec t0;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        long frame_ns = 1000000000L / fps;

        while (!g_stop) {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            float elapsed = (float)(now.tv_sec - t0.tv_sec) + (float)(now.tv_nsec - t0.tv_nsec) * 1e-9f;
            if (duration > 0.0f && elapsed >= duration) break;
            if (tty_stdin && key_pressed()) break;

            float cur_t = t_sec + elapsed;
            float cur_yaw = (yaw_deg * deg2rad) + elapsed * 0.95f;
            float cur_pitch = (pitch_deg * deg2rad) + sinf(elapsed * 0.7f) * 0.16f;

            glUniform2f(loc_res, (float)px_w, (float)px_h);
            glUniform1f(loc_time, cur_t);
            glUniform1f(loc_yaw, cur_yaw);
            glUniform1f(loc_pitch, cur_pitch);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            glFinish();
            glReadPixels(0, 0, px_w, px_h, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

            if (use_kitty) {
                render_kitty(pixels, topdown, b64_buf, px_w, px_h, cols, rows, true, 1);
            } else {
                render_halfblocks(pixels, px_w, px_h, !inline_anim);
                if (inline_anim) {
                    fprintf(stdout, "\x1b[%dA", rows);
                    fflush(stdout);
                }
            }

            struct timespec sl = { .tv_sec = 0, .tv_nsec = frame_ns };
            nanosleep(&sl, NULL);
        }

        if (inline_anim) {
            fprintf(stdout, "\x1b[%dB\r\x1b[0m\x1b[?25h", rows);
        } else {
            fputs("\x1b[0m\x1b[?25h\x1b[?1049l", stdout);
        }
        fflush(stdout);

        if (tty_stdin) {
            tcsetattr(STDIN_FILENO, TCSANOW, &orig_term);
        }
    } else {
        glUniform2f(loc_res, (float)px_w, (float)px_h);
        glUniform1f(loc_time, t_sec);
        glUniform1f(loc_yaw, yaw_deg * deg2rad);
        glUniform1f(loc_pitch, pitch_deg * deg2rad);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        glFinish();
        glReadPixels(0, 0, px_w, px_h, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

        if (ppm_path) {
            if (!write_ppm(ppm_path, pixels, px_w, px_h)) {
                fprintf(stderr, "inferna-ring: failed to write '%s'\n", ppm_path);
                return 1;
            }
        } else if (use_kitty) {
            render_kitty(pixels, topdown, b64_buf, px_w, px_h, cols, rows, false, 1);
            fputc('\n', stdout);
            fflush(stdout);
        } else {
            render_halfblocks(pixels, px_w, px_h, false);
        }
    }

    free(b64_buf);
    free(topdown);
    free(pixels);
    glDeleteVertexArrays(1, &vao);
    glDeleteProgram(prog);
    glDeleteShader(vs);
    glDeleteShader(fs);
    glDeleteTextures(1, &tex);
    glDeleteFramebuffers(1, &fbo);
    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (surf != EGL_NO_SURFACE) eglDestroySurface(dpy, surf);
    eglDestroyContext(dpy, ctx);
    eglTerminate(dpy);
    return 0;
}
