#version 300 es
precision highp float;

out vec4 fragColor;

uniform vec2 u_res;
uniform float u_time;
uniform float u_yaw;
uniform float u_pitch;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

// --- Math & Noise -----------------------------------------------------------
mat2 rot2(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i + vec3(0,0,0));
    float n100 = hash31(i + vec3(1,0,0));
    float n010 = hash31(i + vec3(0,1,0));
    float n110 = hash31(i + vec3(1,1,0));
    float n001 = hash31(i + vec3(0,0,1));
    float n101 = hash31(i + vec3(1,0,1));
    float n011 = hash31(i + vec3(0,1,1));
    float n111 = hash31(i + vec3(1,1,1));
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z);
}

float fbm3(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise3(p);
        p = p * 2.03 + vec3(13.1, 7.7, 5.3);
        a *= 0.5;
    }
    return v;
}

// Seamlessly looping rising 3D FBM using dual-phase flow advection (zero loop pop!)
float loopingFireFbm(vec3 p, float loopPhase, float speedCycles, float riseDist) {
    float p0 = fract(loopPhase * speedCycles);
    float p1 = fract(loopPhase * speedCycles + 0.5);
    float w1 = abs(2.0 * p0 - 1.0);
    float w0 = 1.0 - w1;

    // Slight curling horizontal sway + upward advection
    vec3 q0 = p + vec3(sin(p.y * 2.4 + p0 * TAU) * 0.16, -p0 * riseDist, cos(p.y * 2.0 + p0 * TAU) * 0.12);
    vec3 q1 = p + vec3(sin(p.y * 2.4 + p1 * TAU) * 0.16, -p1 * riseDist, cos(p.y * 2.0 + p1 * TAU) * 0.12);

    float f0 = fbm3(q0);
    float f1 = fbm3(q1 + vec3(7.3, 11.9, 4.1));
    return f0 * w0 + f1 * w1;
}

// --- SDF Primitives ---------------------------------------------------------
float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float sdSeg2(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Crisp Elder Futhark rune glyphs in normalized cell space uv in [-1, 1]^2
float sdRuneGlyph(vec2 uv, int id) {
    float d = 1e5;
    if (id == 0) {
        d = min(d, sdSeg2(uv, vec2(0.0, -0.82), vec2(0.0, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.55, 0.30), vec2(0.55, -0.30)));
    } else if (id == 1) {
        d = min(d, sdSeg2(uv, vec2(-0.35, -0.82), vec2(-0.35, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.35, 0.25), vec2(0.55, 0.80)));
        d = min(d, sdSeg2(uv, vec2(-0.35, -0.18), vec2(0.48, 0.32)));
    } else if (id == 2) {
        d = min(d, sdSeg2(uv, vec2(0.0, -0.82), vec2(0.0, 0.82)));
        d = min(d, sdSeg2(uv, vec2(0.0, 0.15), vec2(-0.58, 0.78)));
        d = min(d, sdSeg2(uv, vec2(0.0, 0.15), vec2(0.58, 0.78)));
    } else if (id == 3) {
        d = min(d, sdSeg2(uv, vec2(0.0, 0.82), vec2(0.56, 0.18)));
        d = min(d, sdSeg2(uv, vec2(0.0, 0.82), vec2(-0.56, 0.18)));
        d = min(d, sdSeg2(uv, vec2(0.56, 0.18), vec2(-0.50, -0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.56, 0.18), vec2(0.50, -0.82)));
    } else if (id == 4) {
        d = min(d, sdSeg2(uv, vec2(0.48, 0.82), vec2(-0.42, 0.12)));
        d = min(d, sdSeg2(uv, vec2(-0.42, 0.12), vec2(0.42, -0.12)));
        d = min(d, sdSeg2(uv, vec2(0.42, -0.12), vec2(-0.48, -0.82)));
    } else if (id == 5) {
        d = min(d, sdSeg2(uv, vec2(-0.40, -0.82), vec2(-0.40, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.40, 0.82), vec2(0.46, 0.34)));
        d = min(d, sdSeg2(uv, vec2(0.46, 0.34), vec2(-0.40, -0.05)));
        d = min(d, sdSeg2(uv, vec2(-0.40, -0.05), vec2(0.50, -0.82)));
    } else if (id == 6) {
        d = min(d, sdSeg2(uv, vec2(-0.50, -0.82), vec2(-0.50, 0.82)));
        d = min(d, sdSeg2(uv, vec2(0.50, -0.82), vec2(0.50, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.50, 0.72), vec2(0.0, 0.18)));
        d = min(d, sdSeg2(uv, vec2(0.50, 0.72), vec2(0.0, 0.18)));
    } else if (id == 7) {
        d = min(d, sdSeg2(uv, vec2(-0.35, -0.82), vec2(-0.35, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.35, 0.78), vec2(0.52, 0.25)));
        d = min(d, sdSeg2(uv, vec2(-0.35, 0.26), vec2(0.52, -0.26)));
    } else if (id == 8) {
        d = min(d, sdSeg2(uv, vec2(0.0, -0.82), vec2(0.0, 0.82)));
        d = min(d, sdSeg2(uv, vec2(0.0, 0.82), vec2(-0.56, 0.26)));
        d = min(d, sdSeg2(uv, vec2(0.0, 0.82), vec2(0.56, 0.26)));
    } else if (id == 9) {
        d = min(d, sdSeg2(uv, vec2(-0.50, -0.82), vec2(-0.50, 0.82)));
        d = min(d, sdSeg2(uv, vec2(0.50, -0.82), vec2(0.50, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.50, 0.76), vec2(0.50, -0.10)));
        d = min(d, sdSeg2(uv, vec2(0.50, 0.76), vec2(-0.50, -0.10)));
    } else if (id == 10) {
        d = min(d, sdSeg2(uv, vec2(-0.35, -0.82), vec2(-0.35, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.35, 0.44), vec2(0.50, 0.0)));
        d = min(d, sdSeg2(uv, vec2(0.50, 0.0), vec2(-0.35, -0.44)));
    } else {
        d = min(d, sdSeg2(uv, vec2(0.0, -0.82), vec2(0.0, 0.82)));
        d = min(d, sdSeg2(uv, vec2(-0.24, 0.76), vec2(0.24, 0.76)));
        d = min(d, sdSeg2(uv, vec2(-0.24, -0.76), vec2(0.24, -0.76)));
    }
    return d;
}

float sdOuterRunes3D(vec3 p, float rad, float ang) {
    float rCenter = 1.075;
    float rBand = 0.082;
    float dShell = max(abs(rad - rCenter) - (rBand + 0.025), abs(p.z) - 0.045);
    if (dShell > 0.05) return dShell;

    float secStep = TAU / 12.0;
    float shifted = ang + PI;
    float secIdx = floor(shifted / secStep);
    float secLocal = mod(shifted, secStep) - secStep * 0.5;

    float span = 0.36;
    float uNorm = (secLocal / span) + 0.5;
    if (uNorm < -0.05 || uNorm > 1.05) {
        return max(abs(secLocal) - span * 0.5, 0.025);
    }

    int slot = int(clamp(floor(uNorm * 4.0), 0.0, 3.0));
    float cellCenterAng = ((float(slot) + 0.5) / 4.0 - 0.5) * span;
    float dAng = secLocal - cellCenterAng;

    float glyphScale = 0.062;
    vec2 uv = vec2((dAng * rCenter) / glyphScale, (rad - rCenter) / glyphScale);

    int sMod = int(mod(secIdx, 4.0));
    int glyphId = 0;
    if (sMod == 0) {
        if (slot == 0) glyphId = 0;
        else if (slot == 1) glyphId = 11;
        else if (slot == 2) glyphId = 2;
        else glyphId = 3;
    } else if (sMod == 1) {
        if (slot == 0) glyphId = 1;
        else if (slot == 1) glyphId = 6;
        else if (slot == 2) glyphId = 5;
        else glyphId = 0;
    } else if (sMod == 2) {
        if (slot == 0) glyphId = 7;
        else if (slot == 1) glyphId = 5;
        else if (slot == 2) glyphId = 9;
        else glyphId = 4;
    } else {
        if (slot == 0) glyphId = 8;
        else if (slot == 1) glyphId = 10;
        else if (slot == 2) glyphId = 3;
        else glyphId = 5;
    }

    float d2 = sdRuneGlyph(uv, glyphId) * glyphScale;
    float strokeR = 0.0052;
    float dStroke = d2 - strokeR;

    float zHalf = 0.013;
    vec2 w = vec2(dStroke, abs(p.z) - zHalf);
    float d3 = length(max(w, 0.0)) + min(max(w.x, w.y), 0.0) - 0.0018;

    float arcBound = abs(secLocal) - span * 0.52;
    return max(d3, arcBound);
}

float sdForgedBar(vec3 p, float x0, float x1, float yOff, float halfW, float halfZ, float zOff) {
    float len = (x1 - x0) * 0.5;
    float cx = (x0 + x1) * 0.5;
    vec3 q = vec3(p.x - cx, p.y - yOff, p.z - zOff);

    vec3 a = abs(q);
    float dBox = sdRoundBox(q, vec3(len, halfW, halfZ), 0.007);
    float dChamfer = (a.y * 0.70 + a.z * 0.71) - (halfW * 0.70 + halfZ * 0.50);
    float d = max(dBox, dChamfer);

    float inFace = smoothstep(halfW * 0.58, halfW * 0.34, a.y) * smoothstep(len, len - 0.05, a.x);
    d += inFace * 0.007;

    return d;
}

float sdSpearSpike(vec3 p, float rStart, float rTip, float baseW, float baseZ) {
    float span = rTip - rStart;
    float t = clamp((p.x - rStart) / span, 0.0, 1.0);
    float w = mix(baseW, 0.0018, pow(t, 0.78));
    float z = mix(baseZ, 0.0028, pow(t, 0.82));

    vec3 q = vec3(p.x - (rStart + span * 0.5), p.y, p.z);
    float dBlade = max(
        sdRoundBox(q, vec3(span * 0.5, w, z), 0.003),
        (abs(q.y) / max(w, 0.003) + abs(q.z) / max(z, 0.003) - 1.15) * min(w, z) * 0.55
    );

    vec3 bp = vec3(p.x - (rStart + span * 0.36), abs(p.y) - w * 0.52, p.z);
    bp.xy = rot2(-0.95) * bp.xy;
    float bt = clamp((bp.y + 0.01) / 0.068, 0.0, 1.0);
    float bw = mix(0.016, 0.0018, bt);
    float dBarb = sdRoundBox(bp - vec3(0.0, 0.022, 0.0), vec3(bw, 0.032, baseZ * 0.32), 0.002);
    return min(dBlade, dBarb);
}

float sdThorn(vec3 p, vec3 base, float dirY, float tiltX, float len) {
    vec3 q = p - base;
    q.y *= dirY;
    q.xy = rot2(tiltX) * q.xy;
    float t = clamp(q.y / len, 0.0, 1.0);
    float w = mix(0.015, 0.0018, t);
    float z = mix(0.013, 0.0018, t);
    return sdRoundBox(q - vec3(0.0, len * 0.5, 0.0), vec3(w, len * 0.5, z), 0.002);
}

vec2 opU(vec2 a, vec2 b) {
    return (a.x < b.x) ? a : b;
}

// --- 3D Inferna Barbed Hexagram Ring + 3D Runes SDF -------------------------
vec2 mapScene(vec3 p) {
    vec2 res = vec2(1e5, 0.0);

    float rad = length(p.xy);
    float ang = atan(p.y, p.x);

    float metalBump = (noise3(p * 28.0) - 0.5) * 0.0028;

    // 1) Slender Outer Cogged Forged Iron Hoop
    float ringR = 0.855;
    float ringHalfW = 0.035;
    float ringHalfZ = 0.044;
    vec2 qRing = vec2(abs(rad - ringR) - ringHalfW, abs(p.z) - ringHalfZ);
    float dRing = length(max(qRing, 0.0)) + min(max(qRing.x, qRing.y), 0.0) - 0.008;
    dRing = max(dRing, (abs(rad - ringR) * 0.65 + abs(p.z) * 0.75) - (ringHalfW * 0.65 + ringHalfZ * 0.56));

    float cogStep = TAU / 36.0;
    float cogAng = mod(ang + cogStep * 0.5, cogStep) - cogStep * 0.5;
    vec3 pCog = vec3(rad - (ringR + ringHalfW + 0.016), cogAng * (ringR + ringHalfW), p.z);
    float dCog = sdRoundBox(pCog, vec3(0.020, 0.022, 0.026), 0.004);
    dRing = min(dRing, dCog);

    float inThornStep = TAU / 24.0;
    float inThornAng = mod(ang + inThornStep * 0.5, inThornStep) - inThornStep * 0.5;
    float it = clamp(((ringR - ringHalfW) - rad) / 0.068, 0.0, 1.0);
    float iw = mix(0.015, 0.0018, it);
    vec3 pInThorn = vec3((ringR - ringHalfW - 0.032) - rad, inThornAng * (ringR - 0.05), p.z);
    float dInThorn = sdRoundBox(pInThorn, vec3(0.034, iw, 0.015), 0.0025);
    dRing = min(dRing, dInThorn);

    res = opU(res, vec2(dRing + metalBump, 1.0));

    // 2) 12 Barbed Gothic Spear-Spikes
    {
        float s12 = floor((ang + PI / 12.0) / (TAU / 12.0));
        float la = ang - s12 * (TAU / 12.0);
        vec3 pSp = vec3(rad * cos(la), rad * sin(la), p.z);

        bool isCardinal = (mod(s12, 3.0) == 0.0);
        bool isEven = (mod(s12, 2.0) == 0.0);
        float tipR = isCardinal ? 1.38 : (isEven ? 1.26 : 1.31);
        float baseW = isCardinal ? 0.076 : 0.066;
        float baseZ = isCardinal ? 0.054 : 0.048;

        float dSp = sdSpearSpike(pSp, ringR - 0.02, tipR, baseW, baseZ);
        res = opU(res, vec2(dSp + metalBump, 1.0));
    }

    // 3) 6 Interlocking Straight Forged Iron Hexagram Bars + Radial Arms + Thorns + Rivets
    float dBars = 1e5;
    float dRivets = 1e5;

    for (int i = 0; i < 6; i++) {
        float a = float(i) * (TAU / 6.0);
        vec3 lp = p;
        lp.xy = rot2(-a) * lp.xy;

        float zWeave = clamp((lp.x - 0.03) * 0.13, -0.050, 0.050);

        float dMain = sdForgedBar(lp, -0.82, 0.82, 0.355, 0.066, 0.048, zWeave);
        dMain = max(dMain, rad - (ringR + 0.012));

        float dArm = sdForgedBar(lp, 0.42, ringR + 0.01, 0.0, 0.042, 0.036, 0.0);

        float dThorns = 1e5;
        dThorns = min(dThorns, sdThorn(lp, vec3(-0.34, 0.355 + 0.058, zWeave),  1.0, -0.25, 0.070));
        dThorns = min(dThorns, sdThorn(lp, vec3( 0.02, 0.355 + 0.058, zWeave),  1.0,  0.14, 0.064));
        dThorns = min(dThorns, sdThorn(lp, vec3( 0.38, 0.355 + 0.058, zWeave),  1.0,  0.28, 0.068));
        dThorns = min(dThorns, sdThorn(lp, vec3(-0.16, 0.355 - 0.058, zWeave), -1.0,  0.22, 0.064));
        dThorns = min(dThorns, sdThorn(lp, vec3( 0.20, 0.355 - 0.058, zWeave), -1.0, -0.18, 0.060));

        float dAll = min(min(dMain, dArm), dThorns) + metalBump;
        dBars = min(dBars, dAll);

        float zSign = (lp.z >= 0.0) ? 1.0 : -1.0;
        for (int r = 0; r < 3; r++) {
            float rx = -0.34 + float(r) * 0.34;
            float rZ = clamp((rx - 0.03) * 0.13, -0.050, 0.050);
            vec3 rv = vec3(rx, 0.355, rZ + 0.045 * zSign);
            dRivets = min(dRivets, length(lp - rv) - 0.016);
        }
        dRivets = min(dRivets, length(lp - vec3(ringR, 0.0, 0.041 * zSign)) - 0.017);
    }

    res = opU(res, vec2(dBars, 1.0));
    res = opU(res, vec2(dRivets, 2.0));

    // 4) 3D Floating Runic Inscriptions
    float dRunes = sdOuterRunes3D(p, rad, ang);
    res = opU(res, vec2(dRunes, 3.0));

    return res;
}

// Seamless dual-phase upward-advecting 3D fBM for fluid photographic hellfire
float fbmFireFlow(vec2 p, float speed, float loopPhase, float zSeed) {
    float p0 = fract(loopPhase * speed);
    float p1 = fract(loopPhase * speed + 0.5);
    float w1 = abs(2.0 * p0 - 1.0);
    float w0 = 1.0 - w1;
    // Slight smoothstep on blend weights keeps contrast crisp during phase crossfade
    w0 = smoothstep(0.0, 1.0, w0);
    w1 = 1.0 - w0;
    float a = fbm3(vec3(p.x, p.y - p0 * 3.6, zSeed + p0 * 0.45));
    float b = fbm3(vec3(p.x, p.y - p1 * 3.6, zSeed + 5.7 + p1 * 0.45));
    return a * w0 + b * w1;
}

// --- Photographic Domain-Warped Hellfire + Rising Ember Sparks ---------------
// Evaluated strictly BEHIND the forged iron ring so the 3D metal & runes stay razor-sharp!
vec4 evalCleanBottomFire(vec2 uv, float loopPhase) {
    // Vertical progress from bottom edge (-1.34) up to slightly above ring center (+0.26)
    float yNorm = clamp((uv.y + 1.34) / 1.60, 0.0, 1.0);

    // 1) Multi-scale upward-stretching domain-warped fluid advection (real licking hellfire!)
    //    Stage A: broad convection currents swaying and curling flame sheets
    float qx = fbmFireFlow(uv * vec2(1.85, 0.95) + vec2(1.7, 0.4), 2.0, loopPhase, 1.3) - 0.5;
    float qy = fbmFireFlow(uv * vec2(1.85, 0.95) + vec2(-2.9, 3.1), 2.0, loopPhase, 4.9) - 0.5;
    float riseWarp = 0.18 + 1.05 * pow(yNorm, 0.80);
    vec2 warped = uv + vec2(qx * 0.54, qy * 0.28) * riseWarp;

    //    Stage B: vertically stretched flame tongues + turbulent curling folds
    //    Higher X frequency than Y frequency naturally stretches turbulence into fierce upward flames!
    float tongues = fbmFireFlow(warped * vec2(3.15, 1.25), 2.0, loopPhase, 9.2);
    vec2 curlCoord = warped * vec2(5.40, 2.25) + vec2((tongues - 0.5) * 1.35, -(tongues - 0.5) * 0.60);
    float licks = fbmFireFlow(curlCoord, 3.0, loopPhase, 14.6);

    //    Sharp ridged filaments create luminous glowing flame sheets & deep dark pockets between them!
    float ridgeBig  = pow(1.0 - abs(2.0 * tongues - 1.0), 1.85);
    float ridgeFine = pow(1.0 - abs(2.0 * licks   - 1.0), 2.35);

    //    Dark-pocket carver slices dark crimson/black negative space down into the fire body
    //    so it NEVER turns into a solid flat yellow blob!
    float pocket = fbmFireFlow(warped * vec2(3.6, 1.55) + vec2(4.1, -1.2), 2.0, loopPhase, 19.8);

    // 2) Natural fire-hearth envelope strictly behind the LOWER half of the ring
    float archW = mix(0.88, 0.46, pow(yNorm, 0.92));
    float xPlume = (uv.x + qx * 0.20 * yNorm) / archW;
    float horizMask = exp(-pow(abs(xPlume), 2.2));

    //    Subtle curling ember wisps on lower-left / lower-right flanks (like the reference!)
    float flankWisp = exp(-pow((abs(uv.x) - 0.72) / 0.30, 2.0))
                    * exp(-pow((uv.y + 0.54) / 0.42, 2.0))
                    * smoothstep(0.50, 0.82, tongues * 0.65 + licks * 0.55);

    float vertDecay = pow(1.0 - yNorm, 0.72);

    // 3) Structured flame density: layered translucent tongues + sharp glowing ridges + dark hollows
    float flameShape = tongues * 0.52 + ridgeBig * 0.34 + ridgeFine * 0.26 - (1.0 - pocket) * 0.22;
    float T = horizMask * vertDecay * (0.12 + 1.38 * flameShape)
            + flankWisp * 0.58
            - yNorm * 0.28;

    //    Crisp silhouetted flame tongues with dark cutouts + delicate translucent crimson outer wisps
    float coreAlpha = smoothstep(0.18, 0.48, T);
    float wispAlpha = smoothstep(0.06, 0.28, T) * 0.42;
    float density = max(coreAlpha, wispAlpha);

    //    Smooth fade at frame edges (bottom cools to crimson before fading so zero grey/cream edge!)
    float bottomCool = smoothstep(-1.34, -0.96, uv.y);
    float frameFade = smoothstep(-1.34, -1.06, uv.y)
                    * smoothstep(1.32, 0.95, abs(uv.x))
                    * smoothstep(1.30, 0.92, uv.y);
    density = clamp(density * frameFade, 0.0, 0.96);

    // 4) Rich hellfire color temperature (mostly deep crimson & vivid fiery orange;
    //    bright amber-gold ONLY along hot inner filaments & ridges, NEVER a flat yellow wall!)
    float filament = ridgeFine * 0.55 + ridgeBig * 0.45;
    float heat = clamp(
        smoothstep(0.14, 0.98, T) * 0.56
      + filament * coreAlpha * (0.46 - 0.16 * yNorm),
        0.0, 1.0
    ) * (0.28 + 0.72 * bottomCool);

    vec3 cCrimson = vec3(0.38, 0.012, 0.002);
    vec3 cScarlet = vec3(0.84, 0.090, 0.006);
    vec3 cOrange  = vec3(1.00, 0.290, 0.018);
    vec3 cAmber   = vec3(1.00, 0.620, 0.085);
    vec3 cHotGold = vec3(1.00, 0.880, 0.380);

    vec3 fireCol = mix(cCrimson, cScarlet, smoothstep(0.03, 0.26, heat));
    fireCol = mix(fireCol, cOrange,  smoothstep(0.24, 0.54, heat));
    fireCol = mix(fireCol, cAmber,   smoothstep(0.54, 0.80, heat));
    fireCol = mix(fireCol, cHotGold, smoothstep(0.82, 0.99, heat));

    // 5) Crisp elongated rising ember sparks drifting cleanly around the dark background
    vec3 sparkCol = vec3(0.0);
    float sparkAlpha = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float scale = (layer == 0) ? 7.0 : 10.5;
        float speed = (layer == 0) ? 2.0 : 3.0;
        float sp0 = fract(loopPhase * speed);
        float sp1 = fract(loopPhase * speed + 0.5);
        float sw1 = abs(2.0 * sp0 - 1.0);
        float sw0 = 1.0 - sw1;

        for (int ph = 0; ph < 2; ph++) {
            float sp = (ph == 0) ? sp0 : sp1;
            float sw = (ph == 0) ? sw0 : sw1;
            vec2 suv = uv * scale;
            suv.y -= sp * 4.0;
            suv.x += sin(suv.y * 0.65 + float(layer) * 3.1) * 0.32;
            vec2 id = floor(suv);
            vec2 f = fract(suv) - 0.5;
            float h = hash21(id + vec2(float(layer) * 31.7, float(ph) * 19.3));
            if (h > 0.895) {
                vec2 jitter = (vec2(fract(h * 17.3), fract(h * 43.1)) - 0.5) * 0.55;
                vec2 d = f - jitter;
                float slant = (fract(h * 61.1) - 0.5) * 0.35;
                d.x += d.y * slant;
                d.x *= 2.35;
                d.y *= 0.82;
                float glow = smoothstep(0.20, 0.015, length(d)) * sw;
                float sFade = smoothstep(1.30, 0.96, abs(uv.x))
                            * smoothstep(1.30, 0.96, abs(uv.y));
                glow *= sFade;
                vec3 sc = mix(vec3(1.00, 0.24, 0.02), vec3(1.00, 0.56, 0.08), fract(h * 91.7));
                sparkCol += sc * glow * 1.25;
                sparkAlpha = max(sparkAlpha, glow * 0.95);
            }
        }
    }

    vec3 outCol = fireCol * density + sparkCol * (1.0 - density * 0.55);
    float outAlpha = clamp(max(density, sparkAlpha), 0.0, 1.0);
    return vec4(outCol, outAlpha);
}

vec3 calcNormal(vec3 p) {
    vec2 e = vec2(0.0014, -0.0014);
    return normalize(
        e.xyy * mapScene(p + e.xyy).x +
        e.yyx * mapScene(p + e.yyx).x +
        e.yxy * mapScene(p + e.yxy).x +
        e.xxx * mapScene(p + e.xxx).x
    );
}

float calcAO(vec3 p, vec3 n) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 5; i++) {
        float h = 0.018 + 0.042 * float(i);
        float d = mapScene(p + h * n).x;
        occ += (h - d) * sca;
        sca *= 0.72;
    }
    return clamp(1.0 - 3.2 * occ, 0.10, 1.0);
}

float calcSoftShadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float t = mint;
    for (int i = 0; i < 22; i++) {
        float h = mapScene(ro + rd * t).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.018, 0.16);
        if (res < 0.005 || t > maxt) break;
    }
    return clamp(res, 0.08, 1.0);
}

vec4 renderSample(vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * u_res) / min(u_res.x, u_res.y);
    uv *= 2.65;

    float loopPhase = fract(u_time * (2.6 / TAU));

    // Shift ring slightly upward so graceful bottom flames have breathing room underneath
    vec2 ringUV = uv - vec2(0.0, 0.12);

    vec3 ro = vec3(0.0, 0.0, 3.18);
    vec3 rd = normalize(vec3(ringUV * 0.48, -1.0));

    mat2 rPitch = rot2(u_pitch);
    mat2 rYaw = rot2(u_yaw);
    ro.yz = rPitch * ro.yz;
    rd.yz = rPitch * rd.yz;
    ro.xz = rYaw * ro.xz;
    rd.xz = rYaw * rd.xz;

    // Raymarch solid 3D forged ring + floating runes
    float bDot = dot(ro, rd);
    float cSolid = dot(ro, ro) - 1.48 * 1.48;
    float discSolid = bDot * bDot - cSolid;
    float t = 0.0;
    float hitMat = 0.0;
    bool hit = false;

    if (discSolid >= 0.0) {
        t = max(0.0, -bDot - sqrt(discSolid));
        float tSolidMax = -bDot + sqrt(discSolid);
        for (int i = 0; i < 80; i++) {
            vec3 p = ro + rd * t;
            vec2 h = mapScene(p);
            if (h.x < 0.0013) {
                hit = true;
                hitMat = h.y;
                break;
            }
            t += h.x * 0.82;
            if (t > tSolidMax) break;
        }
    }

    if (hit) {
        vec3 p = ro + rd * t;
        vec3 n = calcNormal(p);
        vec3 v = -rd;
        float ao = calcAO(p, n);
        float grain = fbm3(p * 20.0);

        float flicker = 0.90 + 0.10 * sin(loopPhase * TAU * 4.0 + p.x * 2.5);

        vec3 surfCol;
        if (hitMat > 2.5) {
            // 3D Floating Runes: warm burnt rust-orange / forged copper (crisp & readable!)
            float pulse = 0.85 + 0.15 * sin(loopPhase * TAU * 2.0 + atan(p.y, p.x) * 4.0);
            vec3 l1 = normalize(vec3(-0.55, 0.78, 0.85));
            float diff = max(dot(n, l1), 0.0);
            float spec = pow(max(dot(n, normalize(l1 + v)), 0.0), 56.0);
            float fresnel = pow(1.0 - max(dot(n, v), 0.0), 2.4);
            vec3 baseCopper = vec3(0.16, 0.055, 0.022);
            vec3 rustEmber  = mix(vec3(0.46, 0.135, 0.032), vec3(0.68, 0.21, 0.048), pulse);
            surfCol = baseCopper * (0.35 + 0.85 * diff)
                    + rustEmber * (0.28 + 0.44 * diff)
                    + vec3(0.88, 0.40, 0.16) * (spec * 0.75 + fresnel * 0.34);
        } else {
            float dCenter = mapScene(p).x;
            float edgeWear = clamp(abs(mapScene(p + n * 0.014).x - dCenter - 0.014) * 52.0, 0.0, 1.0);

            vec3 ironDeep  = vec3(0.040, 0.017, 0.012);
            vec3 ironRust  = vec3(0.115, 0.048, 0.030);
            vec3 edgeSteel = vec3(0.45,  0.26,  0.18);

            vec3 albedo = mix(ironDeep, ironRust, grain * 0.85);
            albedo = mix(albedo, edgeSteel, edgeWear * 0.65);
            if (hitMat > 1.5) {
                albedo = mix(albedo, edgeSteel, 0.50);
            }

            float metallic = 0.88;
            float shininess = mix(48.0, 96.0, edgeWear);

            // Key studio light + warm orange fire-light coming specifically from BELOW!
            vec3 l1 = normalize(vec3(-0.52, 0.78, 0.88));
            vec3 c1 = vec3(1.00, 0.86, 0.74) * 1.90;
            float sh1 = calcSoftShadow(p + n * 0.007, l1, 0.02, 2.4, 12.0);

            // Strong warm firelight shining upward from the bottom flames onto underside of bars!
            vec3 lFire = normalize(vec3(0.05, -0.92, 0.38));
            float bottomProximity = smoothstep(0.85, -0.95, p.y);
            vec3 cFire = vec3(1.00, 0.34, 0.06) * (0.95 + 1.15 * bottomProximity) * flicker;

            vec3 l3 = normalize(vec3(0.20, 0.30, -0.92));
            vec3 c3 = vec3(0.95, 0.56, 0.34) * 1.15;

            vec3 lit = vec3(0.0);
            {
                float diff = max(dot(n, l1), 0.0);
                vec3 h = normalize(l1 + v);
                float spec = pow(max(dot(n, h), 0.0), shininess);
                vec3 specCol = mix(vec3(1.0), albedo * 2.3 + vec3(0.24, 0.15, 0.11), metallic);
                lit += (albedo * (1.0 - metallic * 0.40) * diff + specCol * spec * 1.45) * c1 * sh1;
            }
            {
                float diff = max(dot(n, lFire), 0.0);
                vec3 h = normalize(lFire + v);
                float spec = pow(max(dot(n, h), 0.0), shininess * 0.55);
                vec3 specCol = mix(vec3(1.0), albedo * 1.9 + vec3(0.35, 0.14, 0.04), metallic);
                lit += (albedo * diff + specCol * spec * 0.90) * cFire;
            }
            {
                float diff = max(dot(n, l3), 0.0);
                vec3 h = normalize(l3 + v);
                float spec = pow(max(dot(n, h), 0.0), shininess * 0.5);
                lit += (albedo * 0.30 * diff + edgeSteel * spec * 0.85) * c3;
            }

            float fresnel = pow(1.0 - max(dot(n, v), 0.0), 2.9);
            vec3 rim = mix(vec3(0.75, 0.45, 0.30), vec3(1.00, 0.40, 0.10), bottomProximity) * fresnel * 0.72;

            vec3 ambient = albedo * vec3(0.24, 0.15, 0.12);
            surfCol = (ambient + lit) * ao + rim;
        }

        surfCol = (surfCol * (2.51 * surfCol + 0.03)) / (surfCol * (2.43 * surfCol + 0.59) + 0.14);
        surfCol = pow(clamp(surfCol, 0.0, 1.0), vec3(1.0 / 2.12));
        return vec4(surfCol, 1.0);
    }

    // Ray missed the solid ring: render crisp bottom flames + rising sparks strictly BEHIND the ring!
    vec4 bg = evalCleanBottomFire(uv, loopPhase);
    if (bg.a <= 0.002) return vec4(0.0);
    vec3 straightBg = clamp(bg.rgb / max(bg.a, 0.02), 0.0, 1.0);
    straightBg = pow(straightBg, vec3(1.0 / 1.55));
    return vec4(straightBg * bg.a, bg.a);
}

void main() {
    // 2x2 rotated-grid supersampling anti-aliasing
    vec4 acc = vec4(0.0);
    acc += renderSample(gl_FragCoord.xy + vec2(-0.375, -0.125));
    acc += renderSample(gl_FragCoord.xy + vec2( 0.125, -0.375));
    acc += renderSample(gl_FragCoord.xy + vec2( 0.375,  0.125));
    acc += renderSample(gl_FragCoord.xy + vec2(-0.125,  0.375));
    acc *= 0.25;

    if (acc.a > 0.002) {
        acc.rgb /= acc.a;
    }
    fragColor = acc;
}
