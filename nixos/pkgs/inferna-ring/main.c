#define _POSIX_C_SOURCE 200809L
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <errno.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>

#ifndef DEFAULT_SHADER_PATH
#define DEFAULT_SHADER_PATH "ring.frag"
#endif

static volatile sig_atomic_t g_stop = 0;

static void handle_sig(int sig) {
    (void)sig;
    g_stop = 1;
}

static char *read_entire_file(const char *path, size_t *out_len) {
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
    if (out_len) *out_len = (size_t)sz;
    fclose(f);
    return buf;
}

static uint64_t fnv1a_hash(uint64_t h, const void *data, size_t len) {
    const uint8_t *p = (const uint8_t *)data;
    for (size_t i = 0; i < len; i++) {
        h ^= (uint64_t)p[i];
        h *= 1099511628211ULL;
    }
    return h;
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

static void flip_rgba_vertical(const uint8_t *src, uint8_t *dst, int w, int h) {
    size_t row_bytes = (size_t)w * 4;
    for (int y = 0; y < h; y++) {
        memcpy(dst + (size_t)y * row_bytes, src + (size_t)(h - 1 - y) * row_bytes, row_bytes);
    }
}

static void emit_kitty_chunks(const char *header_fmt_prefix, const uint8_t *payload,
                              size_t payload_len, char *b64_buf) {
    size_t b64_len = base64_encode(payload, payload_len, b64_buf);
    const size_t chunk_sz = 4096;
    size_t off = 0;
    bool first = true;

    while (off < b64_len) {
        size_t n = b64_len - off;
        if (n > chunk_sz) n = chunk_sz;
        int more = (off + n < b64_len) ? 1 : 0;

        if (first) {
            fprintf(stdout, "\x1b_G%s,m=%d;", header_fmt_prefix, more);
            first = false;
        } else {
            fprintf(stdout, "\x1b_Gm=%d;", more);
        }
        fwrite(b64_buf + off, 1, n, stdout);
        fputs("\x1b\\", stdout);
        off += n;
    }
}

static void render_kitty_single(const uint8_t *gl_rgba, uint8_t *topdown, char *b64_buf,
                                int w, int h, int cols, int rows, bool keep_cursor, uint32_t img_id) {
    flip_rgba_vertical(gl_rgba, topdown, w, h);
    size_t raw_len = (size_t)w * (size_t)h * 4;
    uLongf comp_len = compressBound((uLong)raw_len);
    uint8_t *comp = malloc((size_t)comp_len);
    char hdr[192];

    fputs("\x1b[?2026h", stdout);
    if (comp && compress2(comp, &comp_len, topdown, (uLong)raw_len, 1) == Z_OK) {
        snprintf(hdr, sizeof(hdr), "a=T,f=32,o=z,s=%d,v=%d,c=%d,r=%d,i=%u,p=1,q=2,C=%d",
                 w, h, cols, rows, img_id, keep_cursor ? 1 : 0);
        emit_kitty_chunks(hdr, comp, (size_t)comp_len, b64_buf);
    } else {
        snprintf(hdr, sizeof(hdr), "a=T,f=32,s=%d,v=%d,c=%d,r=%d,i=%u,p=1,q=2,C=%d",
                 w, h, cols, rows, img_id, keep_cursor ? 1 : 0);
        emit_kitty_chunks(hdr, topdown, raw_len, b64_buf);
    }
    fputs("\x1b[?2026l", stdout);
    fflush(stdout);
    free(comp);
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

static void png_write_u32_be(FILE *f, uint32_t v) {
    uint8_t b[4] = {
        (uint8_t)((v >> 24) & 0xFFu),
        (uint8_t)((v >> 16) & 0xFFu),
        (uint8_t)((v >>  8) & 0xFFu),
        (uint8_t)(v & 0xFFu),
    };
    fwrite(b, 1, 4, f);
}

static void png_write_chunk(FILE *f, const char tag[4], const uint8_t *data, uint32_t len) {
    png_write_u32_be(f, len);
    fwrite(tag, 1, 4, f);
    if (len > 0) fwrite(data, 1, len, f);
    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const Bytef *)tag, 4);
    if (len > 0) crc = crc32(crc, data, len);
    png_write_u32_be(f, (uint32_t)crc);
}

static bool write_png_rgb_bg(const char *path, const uint8_t *rgba, int w, int h,
                             uint8_t bg_r, uint8_t bg_g, uint8_t bg_b) {
    size_t row_stride = (size_t)w * 3 + 1;
    size_t raw_sz = row_stride * (size_t)h;
    uint8_t *raw = malloc(raw_sz);
    uLongf zcap = compressBound((uLong)raw_sz);
    uint8_t *zbuf = malloc((size_t)zcap);
    if (!raw || !zbuf) {
        free(raw);
        free(zbuf);
        return false;
    }

    for (int y = 0; y < h; y++) {
        uint8_t *dst = raw + (size_t)y * row_stride;
        dst[0] = 0; // PNG filter: None
        const uint8_t *src_row = rgba + (size_t)(h - 1 - y) * (size_t)w * 4;
        for (int x = 0; x < w; x++) {
            const uint8_t *p = src_row + (size_t)x * 4;
            float a = p[3] / 255.0f;
            float ia = 1.0f - a;
            dst[1 + x * 3 + 0] = (uint8_t)(p[0] * a + bg_r * ia + 0.5f);
            dst[1 + x * 3 + 1] = (uint8_t)(p[1] * a + bg_g * ia + 0.5f);
            dst[1 + x * 3 + 2] = (uint8_t)(p[2] * a + bg_b * ia + 0.5f);
        }
    }

    uLongf zlen = zcap;
    if (compress2(zbuf, &zlen, raw, (uLong)raw_sz, 9) != Z_OK) {
        free(raw);
        free(zbuf);
        return false;
    }

    FILE *f = fopen(path, "wb");
    if (!f) {
        free(raw);
        free(zbuf);
        return false;
    }

    static const uint8_t sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    fwrite(sig, 1, 8, f);

    uint8_t ihdr[13] = {
        (uint8_t)((w >> 24) & 0xFF), (uint8_t)((w >> 16) & 0xFF),
        (uint8_t)((w >>  8) & 0xFF), (uint8_t)(w & 0xFF),
        (uint8_t)((h >> 24) & 0xFF), (uint8_t)((h >> 16) & 0xFF),
        (uint8_t)((h >>  8) & 0xFF), (uint8_t)(h & 0xFF),
        8, 2, 0, 0, 0 // 8-bit RGB
    };
    png_write_chunk(f, "IHDR", ihdr, 13);
    png_write_chunk(f, "IDAT", zbuf, (uint32_t)zlen);
    png_write_chunk(f, "IEND", NULL, 0);

    fclose(f);
    free(raw);
    free(zbuf);
    return true;
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

// Binary cache format for pre-rendered compressed Kitty animation loops:
//   [4B magic "IRK1"][4B width][4B height][4B nframes][4B gap_ms]
//   repeated nframes times: [4B zlen][zlen bytes of zlib-compressed top-down RGBA]
#define CACHE_MAGIC 0x314B5249u

static int print_side_panel_inline(const char *side_cmd, int cols, int rows) {
    char *side_lines[64];
    int side_count = 0;
    if (side_cmd) {
        FILE *pf = popen(side_cmd, "r");
        if (pf) {
            char line[2048];
            while (side_count < 64 && fgets(line, sizeof(line), pf)) {
                size_t ln = strlen(line);
                while (ln > 0 && (line[ln - 1] == '\n' || line[ln - 1] == '\r')) line[--ln] = '\0';
                side_lines[side_count++] = strdup(line);
            }
            pclose(pf);
        }
    }

    int total_rows = (side_count > rows) ? side_count : rows;
    for (int r = 0; r < total_rows; r++) fputc('\n', stdout);
    fprintf(stdout, "\x1b[%dA", total_rows);

    if (side_count > 0) {
        int side_col = cols + 4;
        int top_pad = (total_rows - side_count) / 2;
        for (int r = 0; r < side_count; r++) {
            if (top_pad + r > 0) fprintf(stdout, "\x1b[%dB", top_pad + r);
            fprintf(stdout, "\r\x1b[%dC%s\x1b[0m", side_col, side_lines[r]);
            if (top_pad + r > 0) fprintf(stdout, "\x1b[%dA", top_pad + r);
        }
        fputc('\r', stdout);
    }

    for (int r = 0; r < side_count; r++) free(side_lines[r]);
    return total_rows;
}

static bool play_kitty_loop_from_cache(const char *cache_path, int cols, int rows,
                                       const char *side_cmd, uint32_t img_id) {
    FILE *f = fopen(cache_path, "rb");
    if (!f) return false;

    uint32_t hdr[5];
    if (fread(hdr, sizeof(uint32_t), 5, f) != 5 || hdr[0] != CACHE_MAGIC) {
        fclose(f);
        return false;
    }
    int w = (int)hdr[1];
    int h = (int)hdr[2];
    int nframes = (int)hdr[3];
    int gap_ms = (int)hdr[4];
    if (w < 16 || h < 16 || nframes < 2 || nframes > 360) {
        fclose(f);
        return false;
    }

    size_t max_raw = (size_t)w * (size_t)h * 4;
    size_t max_comp = (size_t)compressBound((uLong)max_raw);
    uint8_t *zbuf = malloc(max_comp);
    char *b64 = malloc(((max_comp + 2) / 3) * 4 + 16);
    if (!zbuf || !b64) {
        free(zbuf);
        free(b64);
        fclose(f);
        return false;
    }

    int total_rows = print_side_panel_inline(side_cmd, cols, rows);

    fputs("\x1b[?2026h", stdout);
    char khdr[256];
    for (int k = 0; k < nframes; k++) {
        uint32_t zlen = 0;
        if (fread(&zlen, sizeof(uint32_t), 1, f) != 1 || zlen == 0 || zlen > max_comp) {
            free(zbuf);
            free(b64);
            fclose(f);
            return false;
        }
        if (fread(zbuf, 1, zlen, f) != zlen) {
            free(zbuf);
            free(b64);
            fclose(f);
            return false;
        }

        if (k == 0) {
            snprintf(khdr, sizeof(khdr), "a=T,f=32,o=z,s=%d,v=%d,c=%d,r=%d,i=%u,p=1,q=2,C=1",
                     w, h, cols, rows, img_id);
            emit_kitty_chunks(khdr, zbuf, zlen, b64);
            fprintf(stdout, "\x1b_Ga=a,i=%u,r=1,z=%d,q=2\x1b\\", img_id, gap_ms);
        } else {
            snprintf(khdr, sizeof(khdr), "a=f,f=32,o=z,s=%d,v=%d,i=%u,z=%d,X=1,q=2",
                     w, h, img_id, gap_ms);
            emit_kitty_chunks(khdr, zbuf, zlen, b64);
        }
    }
    // Start native terminal infinite animation loop (s=3 running, v=1 infinite loop)
    fprintf(stdout, "\x1b_Ga=a,i=%u,s=3,v=1,q=2\x1b\\", img_id);
    fprintf(stdout, "\x1b[?2026l\x1b[%dB\r", total_rows);
    fflush(stdout);

    free(zbuf);
    free(b64);
    fclose(f);
    return true;
}

static void ensure_cache_dir(char *out_path, size_t out_sz, uint64_t hash) {
    const char *home = getenv("HOME");
    if (!home) {
        out_path[0] = '\0';
        return;
    }
    char dir1[512], dir2[512];
    snprintf(dir1, sizeof(dir1), "%s/.cache", home);
    mkdir(dir1, 0755);
    snprintf(dir2, sizeof(dir2), "%s/.cache/inferna-ring", home);
    mkdir(dir2, 0755);
    snprintf(out_path, out_sz, "%s/loop-%016llx.bin", dir2, (unsigned long long)hash);
}

static void usage(const char *argv0) {
    fprintf(stderr,
        "Usage: %s [options]\n"
        "  --kitty            High-resolution pixel output via Kitty Graphics Protocol\n"
        "  --kitty-loop       Upload a seamless 360-deg looping animation to Ghostty/Kitty and exit immediately!\n"
        "  --frames <n>       Number of frames for --kitty-loop (default: 48)\n"
        "  --no-cache         Bypass ~/.cache/inferna-ring/ when using --kitty-loop\n"
        "  --size <px>        Pixel resolution for --kitty/--kitty-loop/--ppm (default: 288)\n"
        "  --cols <n>         Display width in terminal columns (default: 32)\n"
        "  --rows <n>         Display height in terminal rows (default: 16)\n"
        "  --yaw <deg>        Initial 3D yaw angle in degrees (default: 20)\n"
        "  --pitch <deg>      Initial 3D pitch angle in degrees (default: -14)\n"
        "  --time <sec>       Shader timestamp (default: 0.0)\n"
        "  --animate          Interactive real-time 3D spin (press any key or Ctrl+C to exit)\n"
        "  --duration <sec>   Optional auto-stop duration when using --animate\n"
        "  --fps <n>          Animation framerate (default: 24 for --kitty-loop, 30 for --animate)\n"
        "  --inline           Animate inline in scrollback instead of alternate screen\n"
        "  --side-cmd <cmd>   Run command (e.g. fastfetch) and print output beside the 3D ring\n"
        "  --ppm <file>       Render to a PPM image file\n"
        "  --png-seq <dir>    Render a seamless 360-deg PNG frame sequence (frame-000.png..)\n"
        "  --shader <path>    Custom GLSL fragment shader path\n",
        argv0);
}

int main(int argc, char **argv) {
    bool use_kitty = false;
    bool kitty_loop = false;
    bool use_cache = true;
    int nframes = 48;
    int size_px = 288;
    int cols = 0;
    int rows = 0;
    float yaw_deg = 20.0f;
    float pitch_deg = -14.0f;
    float t_sec = 0.0f;
    bool animate = false;
    bool inline_anim = false;
    float duration = 0.0f;
    int fps = 0;
    const char *side_cmd = NULL;
    const char *ppm_path = NULL;
    const char *png_seq_dir = NULL;
    const char *shader_path = DEFAULT_SHADER_PATH;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--kitty")) use_kitty = true;
        else if (!strcmp(argv[i], "--kitty-loop")) { kitty_loop = true; use_kitty = true; }
        else if (!strcmp(argv[i], "--no-cache")) use_cache = false;
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc) nframes = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--size") && i + 1 < argc) size_px = atoi(argv[++i]);
        else if ((!strcmp(argv[i], "--cols") || !strcmp(argv[i], "--width")) && i + 1 < argc) cols = atoi(argv[++i]);
        else if ((!strcmp(argv[i], "--rows") || !strcmp(argv[i], "--height")) && i + 1 < argc) rows = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--yaw") && i + 1 < argc) yaw_deg = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--pitch") && i + 1 < argc) pitch_deg = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--time") && i + 1 < argc) t_sec = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--animate")) animate = true;
        else if (!strcmp(argv[i], "--inline")) inline_anim = true;
        else if (!strcmp(argv[i], "--side-cmd") && i + 1 < argc) side_cmd = argv[++i];
        else if (!strcmp(argv[i], "--duration") && i + 1 < argc) duration = strtof(argv[++i], NULL);
        else if (!strcmp(argv[i], "--fps") && i + 1 < argc) fps = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--ppm") && i + 1 < argc) ppm_path = argv[++i];
        else if (!strcmp(argv[i], "--png-seq") && i + 1 < argc) png_seq_dir = argv[++i];
        else if (!strcmp(argv[i], "--shader") && i + 1 < argc) shader_path = argv[++i];
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(argv[0]); return 0; }
        else { fprintf(stderr, "Unknown option: %s\n", argv[i]); usage(argv[0]); return 1; }
    }

    if (cols <= 0) cols = use_kitty ? 32 : 36;
    if (rows <= 0) rows = use_kitty ? 16 : 18;
    if (fps <= 0) fps = kitty_loop ? 24 : 30;
    if (size_px < 64) size_px = 64;
    if (size_px > 1024) size_px = 1024;
    if (nframes < 6) nframes = 6;
    if (nframes > 360) nframes = 360;
    if (fps < 1) fps = 1;
    if (fps > 60) fps = 60;

    int px_w = (use_kitty || ppm_path || png_seq_dir) ? size_px : cols;
    int px_h = (use_kitty || ppm_path || png_seq_dir) ? size_px : rows * 2;
    int gap_ms = 1000 / fps;
    if (gap_ms < 16) gap_ms = 16;

    size_t frag_len = 0;
    char *frag_src = read_entire_file(shader_path, &frag_len);
    if (!frag_src) {
        fprintf(stderr, "inferna-ring: cannot read shader '%s'\n", shader_path);
        return 1;
    }

    // Unique per-invocation Kitty image ID so multiple rings in scrollback never collide
    uint32_t img_id = ((uint32_t)getpid() & 0x7FFFu) + 100u;

    // Fast path: if --kitty-loop is already cached for this exact shader + params, stream in ~8ms!
    char cache_path[600] = {0};
    if (kitty_loop && use_cache) {
        uint64_t h = 14695981039346656037ULL;
        h = fnv1a_hash(h, frag_src, frag_len);
        h = fnv1a_hash(h, &px_w, sizeof(px_w));
        h = fnv1a_hash(h, &px_h, sizeof(px_h));
        h = fnv1a_hash(h, &nframes, sizeof(nframes));
        h = fnv1a_hash(h, &gap_ms, sizeof(gap_ms));
        h = fnv1a_hash(h, &yaw_deg, sizeof(yaw_deg));
        h = fnv1a_hash(h, &pitch_deg, sizeof(pitch_deg));
        ensure_cache_dir(cache_path, sizeof(cache_path), h);
        if (cache_path[0] && play_kitty_loop_from_cache(cache_path, cols, rows, side_cmd, img_id)) {
            free(frag_src);
            return 0;
        }
    }

    // Initialize headless OpenGL ES 3.0 via EGL
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
    size_t max_comp = (size_t)compressBound((uLong)rgba_sz);
    char *b64_buf = use_kitty ? malloc(((max_comp + 2) / 3) * 4 + 16) : NULL;
    if (!pixels || (use_kitty && (!topdown || !b64_buf))) return 1;

    const float deg2rad = 3.14159265359f / 180.0f;
    const float tau = 6.28318530718f;

    if (png_seq_dir) {
        mkdir(png_seq_dir, 0755);
        char out_file[640];
        for (int k = 0; k < nframes; k++) {
            float phase = (float)k / (float)nframes;
            float cur_yaw = (yaw_deg * deg2rad) + phase * tau;
            float cur_pitch = (pitch_deg * deg2rad) + sinf(phase * tau) * 0.14f;
            float cur_t = phase * (tau / 2.6f);

            glUniform2f(loc_res, (float)px_w, (float)px_h);
            glUniform1f(loc_time, cur_t);
            glUniform1f(loc_yaw, cur_yaw);
            glUniform1f(loc_pitch, cur_pitch);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            glFinish();
            glReadPixels(0, 0, px_w, px_h, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

            snprintf(out_file, sizeof(out_file), "%s/frame-%03d.png", png_seq_dir, k);
            if (!write_png_rgb_bg(out_file, pixels, px_w, px_h, 13, 9, 8)) {
                fprintf(stderr, "inferna-ring: failed to write '%s'\n", out_file);
                return 1;
            }
        }
    } else if (kitty_loop) {
        uint8_t *zbuf = malloc(max_comp);
        if (!zbuf) return 1;

        char tmp_cache[640] = {0};
        FILE *cf = NULL;
        if (cache_path[0]) {
            snprintf(tmp_cache, sizeof(tmp_cache), "%s.%d.tmp", cache_path, (int)getpid());
            cf = fopen(tmp_cache, "wb");
            if (cf) {
                uint32_t chdr[5] = { CACHE_MAGIC, (uint32_t)px_w, (uint32_t)px_h, (uint32_t)nframes, (uint32_t)gap_ms };
                fwrite(chdr, sizeof(uint32_t), 5, cf);
            }
        }

        int total_rows = print_side_panel_inline(side_cmd, cols, rows);
        fputs("\x1b[?2026h", stdout);

        char khdr[256];
        for (int k = 0; k < nframes; k++) {
            float phase = (float)k / (float)nframes;
            float cur_yaw = (yaw_deg * deg2rad) + phase * tau;
            float cur_pitch = (pitch_deg * deg2rad) + sinf(phase * tau) * 0.14f;
            float cur_t = phase * (tau / 2.6f);

            glUniform2f(loc_res, (float)px_w, (float)px_h);
            glUniform1f(loc_time, cur_t);
            glUniform1f(loc_yaw, cur_yaw);
            glUniform1f(loc_pitch, cur_pitch);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            glFinish();
            glReadPixels(0, 0, px_w, px_h, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

            flip_rgba_vertical(pixels, topdown, px_w, px_h);
            uLongf zlen = (uLongf)max_comp;
            if (compress2(zbuf, &zlen, topdown, (uLong)rgba_sz, 6) != Z_OK) {
                if (cf) { fclose(cf); unlink(tmp_cache); cf = NULL; }
                break;
            }
            if (cf) {
                uint32_t zl32 = (uint32_t)zlen;
                fwrite(&zl32, sizeof(uint32_t), 1, cf);
                fwrite(zbuf, 1, (size_t)zlen, cf);
            }

            if (k == 0) {
                snprintf(khdr, sizeof(khdr), "a=T,f=32,o=z,s=%d,v=%d,c=%d,r=%d,i=%u,p=1,q=2,C=1",
                         px_w, px_h, cols, rows, img_id);
                emit_kitty_chunks(khdr, zbuf, (size_t)zlen, b64_buf);
                fprintf(stdout, "\x1b_Ga=a,i=%u,r=1,z=%d,q=2\x1b\\", img_id, gap_ms);
            } else {
                snprintf(khdr, sizeof(khdr), "a=f,f=32,o=z,s=%d,v=%d,i=%u,z=%d,X=1,q=2",
                         px_w, px_h, img_id, gap_ms);
                emit_kitty_chunks(khdr, zbuf, (size_t)zlen, b64_buf);
            }
        }

        fprintf(stdout, "\x1b_Ga=a,i=%u,s=3,v=1,q=2\x1b\\", img_id);
        fprintf(stdout, "\x1b[?2026l\x1b[%dB\r", total_rows);
        fflush(stdout);

        if (cf) {
            fclose(cf);
            rename(tmp_cache, cache_path);
        }
        free(zbuf);
    } else if (animate) {
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

        int total_rows = rows;
        if (inline_anim) {
            total_rows = print_side_panel_inline(side_cmd, cols, rows);
            fputs("\x1b[?25l", stdout);
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
                render_kitty_single(pixels, topdown, b64_buf, px_w, px_h, cols, rows, true, img_id);
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
            fprintf(stdout, "\x1b[%dB\r\x1b[0m\x1b[?25h", total_rows);
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
            render_kitty_single(pixels, topdown, b64_buf, px_w, px_h, cols, rows, false, img_id);
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
