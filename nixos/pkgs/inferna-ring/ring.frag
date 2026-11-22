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

// --- SDF Primitives ---------------------------------------------------------
float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// Forged iron bar with chamfered bevel edges & subtle central fuller/ridge
float sdForgedBar(vec3 p, float x0, float x1, float yOff, float halfW, float halfZ, float zOff) {
    float len = (x1 - x0) * 0.5;
    float cx = (x0 + x1) * 0.5;
    vec3 q = vec3(p.x - cx, p.y - yOff, p.z - zOff);

    // Chamfered 45-deg beveled cross-section (thick center, sharp sloped bevels)
    vec3 a = abs(q);
    float dBox = sdRoundBox(q, vec3(len, halfW, halfZ), 0.008);
    // Bevel cut on the (y, z) edges so specular light catches crisp forged edges
    float dChamfer = (a.y * 0.68 + a.z * 0.73) - (halfW * 0.68 + halfZ * 0.52);
    float d = max(dBox, dChamfer);

    // Subtle forged central groove/channel along bar face (like reference)
    float inFace = smoothstep(halfW * 0.62, halfW * 0.35, a.y) * smoothstep(len, len - 0.06, a.x);
    d += inFace * 0.006;

    return d;
}

// Forged barbed dagger/spear spike along +X starting at rStart -> rTip
float sdSpearSpike(vec3 p, float rStart, float rTip, float baseW, float baseZ, bool hasBarbs) {
    float span = rTip - rStart;
    float t = clamp((p.x - rStart) / span, 0.0, 1.0);
    // Concave blade taper toward razor tip
    float w = mix(baseW, 0.002, pow(t, 0.82));
    float z = mix(baseZ, 0.003, pow(t, 0.85));

    vec3 q = vec3(p.x - (rStart + span * 0.5), p.y, p.z);
    // Diamond/ridge blade cross-section (raised sharp ridge along the center!)
    float dBlade = max(
        sdRoundBox(q, vec3(span * 0.5, w, z), 0.004),
        (abs(q.y) / max(w, 0.004) + abs(q.z) / max(z, 0.004) - 1.18) * min(w, z) * 0.55
    );

    if (hasBarbs) {
        // Two small backward-swept side barbs near the base of the spear
        vec3 bp = vec3(p.x - (rStart + span * 0.24), abs(p.y) - baseW * 0.58, p.z);
        bp.xy = rot2(-0.55) * bp.xy;
        float bt = clamp((bp.y + 0.02) / 0.085, 0.0, 1.0);
        float bw = mix(0.022, 0.002, bt);
        float dBarb = sdRoundBox(bp - vec3(0.0, 0.025, 0.0), vec3(bw, 0.042, baseZ * 0.38), 0.003);
        dBlade = min(dBlade, dBarb);
    }

    return dBlade;
}

// Tiny sharp thorn protruding from a bar edge
float sdThorn(vec3 p, vec3 base, float dirY, float tiltX, float len) {
    vec3 q = p - base;
    q.y *= dirY;
    q.xy = rot2(tiltX) * q.xy;
    float t = clamp(q.y / len, 0.0, 1.0);
    float w = mix(0.017, 0.002, t);
    float z = mix(0.015, 0.002, t);
    return sdRoundBox(q - vec3(0.0, len * 0.5, 0.0), vec3(w, len * 0.5, z), 0.002);
}

// Material IDs:
// 1.0 = Dark Forged Iron (bars, ring, spikes, thorns)
// 2.0 = Burnished Bronze/Iron Rivets & High-wear Edges
vec2 opU(vec2 a, vec2 b) {
    return (a.x < b.x) ? a : b;
}

// --- 3D Inferna Barbed Hexagram Ring SDF (Faithful to Reference) ------------
vec2 mapScene(vec3 p) {
    vec2 res = vec2(1e5, 0.0);

    float rad = length(p.xy);
    float ang = atan(p.y, p.x);

    // Subtle forged hammered iron micro-texture
    float metalBump = (noise3(p * 26.0) - 0.5) * 0.0032;

    // 1) Thin Outer Forged Iron Ring (matches slender cogged hoop in reference)
    float ringR = 0.845;
    float ringHalfW = 0.036;
    float ringHalfZ = 0.044;
    vec2 qRing = vec2(abs(rad - ringR) - ringHalfW, abs(p.z) - ringHalfZ);
    float dRing = length(max(qRing, 0.0)) + min(max(qRing.x, qRing.y), 0.0) - 0.009;
    // Bevel the outer hoop
    dRing = max(dRing, (abs(rad - ringR) * 0.65 + abs(p.z) * 0.75) - (ringHalfW * 0.65 + ringHalfZ * 0.58));

    // Outer squared gear cogs between spikes (36 around perimeter, masked away from spike bases)
    float cogStep = TAU / 36.0;
    float cogAng = mod(ang + cogStep * 0.5, cogStep) - cogStep * 0.5;
    vec3 pCog = vec3(rad - (ringR + ringHalfW + 0.018), cogAng * (ringR + ringHalfW), p.z);
    float dCog = sdRoundBox(pCog, vec3(0.022, 0.024, 0.028), 0.005);
    dRing = min(dRing, dCog);

    // Small inward thorns around the inner edge of the ring (24 around perimeter)
    float inThornStep = TAU / 24.0;
    float inThornAng = mod(ang + inThornStep * 0.5, inThornStep) - inThornStep * 0.5;
    // Slight angular offset so thorns sit nicely between intersections
    float it = clamp(((ringR - ringHalfW) - rad) / 0.075, 0.0, 1.0);
    float iw = mix(0.017, 0.002, it);
    vec3 pInThorn = vec3((ringR - ringHalfW - 0.036) - rad, inThornAng * (ringR - 0.05), p.z);
    float dInThorn = sdRoundBox(pInThorn, vec3(0.038, iw, 0.016), 0.003);
    dRing = min(dRing, dInThorn);

    res = opU(res, vec2(dRing + metalBump, 1.0));

    // 2) 12 Dramatic Barbed Spear-Spikes radiating from the outer ring (every 30 deg)
    // 6 Primary spikes (at 0, 60, 120, 180, 240, 300 deg — wait: 90, 150, 210, 270, 330, 30 + 0, 60, 120, 180, 240, 300)
    // Cardinal 12/3/6/9 o'clock + diagonals = all 12 positions every 30 deg!
    // Primary 6 (aligned with 0, 60, 120, 180, 240, 300 -> 3 o'clock & 9 o'clock horizontal + 60 deg)
    // Secondary 6 (at 30, 90, 150, 210, 270, 330 -> 12 o'clock & 6 o'clock vertical + 60 deg)
    {
        // Fold into 30-degree sector for all 12 spikes
        float s12 = floor((ang + PI / 12.0) / (TAU / 12.0));
        float la = ang - s12 * (TAU / 12.0);
        vec3 pSp = vec3(rad * cos(la), rad * sin(la), p.z);

        // Alternate slightly between cardinal/star-tip spikes (longer) and intermediate spikes
        bool isMain = (mod(s12, 2.0) == 0.0);
        // Make 12, 3, 6, 9 o'clock extra dramatic just like the reference!
        bool isCardinal = (mod(s12, 3.0) == 0.0);
        float tipR = isCardinal ? 1.36 : (isMain ? 1.24 : 1.28);
        float baseW = isCardinal ? 0.078 : 0.068;
        float baseZ = isCardinal ? 0.056 : 0.048;

        float dSp = sdSpearSpike(pSp, ringR - 0.02, tipR, baseW, baseZ, true);
        res = opU(res, vec2(dSp + metalBump, 1.0));
    }

    // 3) 6 Interlocking Forged Iron Hexagram Bars + Radial Struts + Barbed Thorns + Rivets
    float dBars = 1e5;
    float dRivets = 1e5;

    for (int i = 0; i < 6; i++) {
        // Rotate by 60 deg per bar (0 deg = horizontal top bar at y = +0.345, matching reference!)
        float a = float(i) * (TAU / 6.0);
        vec3 lp = p;
        lp.xy = rot2(-a) * lp.xy;

        // True 3D over/under interlocking weave:
        // Left side goes UNDER neighbor, right side passes OVER neighbor!
        float zWeave = clamp((lp.x - 0.04) * 0.125, -0.048, 0.048);

        // Main hexagram forged iron chord bar (extends from left ring curve to right ring junction)
        // Slight graceful hook/curve down at the left tip as it meets the outer ring (like reference!)
        float leftCurve = smoothstep(-0.48, -0.78, lp.x);
        vec3 cp = lp;
        cp.y += leftCurve * 0.11;

        float dMain = sdForgedBar(cp, -0.78, 0.72, 0.345, 0.064, 0.046, zWeave);

        // Short horizontal/radial arm connecting the star corner cleanly out to the spike base on the ring
        float dArm = sdForgedBar(lp, 0.44, 0.87, 0.0, 0.044, 0.036, 0.0);

        // Sharp little forged thorns sprouting along both edges of each bar (iconic Inferna detail!)
        float dThorns = 1e5;
        dThorns = min(dThorns, sdThorn(lp, vec3(-0.32, 0.345 + 0.056, zWeave),  1.0, -0.25, 0.075));
        dThorns = min(dThorns, sdThorn(lp, vec3( 0.02, 0.345 + 0.056, zWeave),  1.0,  0.15, 0.068));
        dThorns = min(dThorns, sdThorn(lp, vec3( 0.38, 0.345 + 0.056, zWeave),  1.0,  0.30, 0.072));
        dThorns = min(dThorns, sdThorn(lp, vec3(-0.14, 0.345 - 0.056, zWeave), -1.0,  0.22, 0.068));
        dThorns = min(dThorns, sdThorn(lp, vec3( 0.22, 0.345 - 0.056, zWeave), -1.0, -0.18, 0.064));

        float dAll = min(min(dMain, dArm), dThorns) + metalBump;
        dBars = min(dBars, dAll);

        // Raised iron rivets on front & back of bars and spike junctions
        float zSign = (lp.z >= 0.0) ? 1.0 : -1.0;
        for (int r = 0; r < 3; r++) {
            float rx = -0.34 + float(r) * 0.34;
            float rZ = clamp((rx - 0.04) * 0.125, -0.048, 0.048);
            vec3 rv = vec3(rx, 0.345, rZ + 0.044 * zSign);
            dRivets = min(dRivets, length(lp - rv) - 0.017);
        }
        // Rivet at ring-spike junction
        dRivets = min(dRivets, length(lp - vec3(ringR, 0.0, 0.042 * zSign)) - 0.018);
    }

    res = opU(res, vec2(dBars, 1.0));
    res = opU(res, vec2(dRivets, 2.0));

    return res;
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
    return clamp(1.0 - 3.0 * occ, 0.12, 1.0);
}

float calcSoftShadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float t = mint;
    for (int i = 0; i < 24; i++) {
        float h = mapScene(ro + rd * t).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.018, 0.16);
        if (res < 0.005 || t > maxt) break;
    }
    return clamp(res, 0.12, 1.0);
}

vec4 renderSample(vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * u_res) / min(u_res.x, u_res.y);
    uv *= 2.85;

    vec3 ro = vec3(0.0, 0.0, 3.25);
    vec3 rd = normalize(vec3(uv * 0.46, -1.0));

    mat2 rPitch = rot2(u_pitch);
    mat2 rYaw = rot2(u_yaw);
    ro.yz = rPitch * ro.yz;
    rd.yz = rPitch * rd.yz;
    ro.xz = rYaw * ro.xz;
    rd.xz = rYaw * rd.xz;

    // Bounding sphere quick reject (max spike tip radius ~1.40)
    float bDot = dot(ro, rd);
    float cSph = dot(ro, ro) - 1.46 * 1.46;
    float disc = bDot * bDot - cSph;
    if (disc < 0.0) {
        return vec4(0.0);
    }

    float t = max(0.0, -bDot - sqrt(disc));
    float tMax = -bDot + sqrt(disc);
    float hitMat = 0.0;
    bool hit = false;

    for (int i = 0; i < 76; i++) {
        vec3 p = ro + rd * t;
        vec2 h = mapScene(p);
        if (h.x < 0.0014) {
            hit = true;
            hitMat = h.y;
            break;
        }
        t += h.x * 0.85;
        if (t > tMax) break;
    }

    if (!hit) {
        return vec4(0.0);
    }

    vec3 p = ro + rd * t;
    vec3 n = calcNormal(p);
    vec3 v = -rd;
    float ao = calcAO(p, n);
    float grain = fbm3(p * 18.0);

    // Curvature / edge-wear approximation (makes beveled forged iron edges shine like reference!)
    float dCenter = mapScene(p).x;
    float edgeWear = clamp(abs(mapScene(p + n * 0.015).x - dCenter - 0.015) * 45.0, 0.0, 1.0);

    // Reference palette: deep dark chocolate/oxidized forged iron + warm burnished steel bevels
    vec3 ironDark  = vec3(0.11, 0.052, 0.036); // deep dark rusted iron
    vec3 ironMid   = vec3(0.24, 0.115, 0.075); // warm forged bronze-iron
    vec3 edgeSteel = vec3(0.56, 0.35,  0.24);  // burnished bevel highlight

    vec3 albedo = mix(ironDark, ironMid, grain * 0.85);
    albedo = mix(albedo, edgeSteel, edgeWear * 0.55);
    if (hitMat > 1.5) {
        // Rivets slightly brighter burnished iron
        albedo = mix(albedo, edgeSteel, 0.45);
    }

    float metallic = 0.86;
    float shininess = mix(42.0, 88.0, edgeWear);

    // Crisp 3-point metallic studio lighting matching reference contrast
    vec3 l1 = normalize(vec3(-0.52, 0.78, 0.88));
    vec3 c1 = vec3(1.00, 0.88, 0.78) * 2.15;
    float sh1 = calcSoftShadow(p + n * 0.007, l1, 0.02, 2.5, 12.0);

    vec3 l2 = normalize(vec3(0.65, -0.65, 0.60));
    vec3 c2 = vec3(0.95, 0.55, 0.36) * 1.15;

    vec3 l3 = normalize(vec3(0.10, 0.35, -0.92));
    vec3 c3 = vec3(0.95, 0.65, 0.48) * 1.25;

    vec3 lit = vec3(0.0);
    {
        float diff = max(dot(n, l1), 0.0);
        vec3 h = normalize(l1 + v);
        float spec = pow(max(dot(n, h), 0.0), shininess);
        vec3 specCol = mix(vec3(1.0), albedo * 2.2 + vec3(0.25, 0.16, 0.12), metallic);
        lit += (albedo * (1.0 - metallic * 0.35) * diff + specCol * spec * 1.50) * c1 * sh1;
    }
    {
        float diff = max(dot(n, l2), 0.0);
        vec3 h = normalize(l2 + v);
        float spec = pow(max(dot(n, h), 0.0), shininess * 0.6);
        vec3 specCol = mix(vec3(1.0), albedo * 1.8 + vec3(0.22, 0.12, 0.08), metallic);
        lit += (albedo * diff + specCol * spec * 0.75) * c2;
    }
    {
        float diff = max(dot(n, l3), 0.0);
        vec3 h = normalize(l3 + v);
        float spec = pow(max(dot(n, h), 0.0), shininess * 0.5);
        lit += (albedo * 0.35 * diff + edgeSteel * spec * 0.85) * c3;
    }

    // Crisp metallic Fresnel rim along all spikes, thorns, and bar chamfers
    float fresnel = pow(1.0 - max(dot(n, v), 0.0), 2.8);
    vec3 rim = vec3(0.85, 0.52, 0.36) * fresnel * 0.68;

    vec3 ambient = albedo * vec3(0.26, 0.18, 0.15);
    vec3 col = (ambient + lit) * ao + rim;

    // Filmic tone mapping
    col = (col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14);
    col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / 2.1));

    return vec4(col, 1.0);
}

void main() {
    // 2x2 rotated-grid supersampling anti-aliasing
    vec4 acc = vec4(0.0);
    acc += renderSample(gl_FragCoord.xy + vec2(-0.375, -0.125));
    acc += renderSample(gl_FragCoord.xy + vec2( 0.125, -0.375));
    acc += renderSample(gl_FragCoord.xy + vec2( 0.375,  0.125));
    acc += renderSample(gl_FragCoord.xy + vec2(-0.125,  0.375));
    acc *= 0.25;

    if (acc.a > 0.001) {
        acc.rgb /= acc.a;
    }
    fragColor = acc;
}
