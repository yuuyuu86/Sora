// 草原の Metal シェーダー（実行時にコンパイル）
let meadowShaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct U {
    float4 rt;      // width, height, time, aspect
    float4 sun;     // dir.xyz, intensity
    float4 moon;    // dir.xyz, visibility
    float4 w1;      // cloud, rain, snow, fog
    float4 w2;      // flash, wind, snowGround, exposure
    float4 misc;    // showSunMoon, cloudOffX, cloudOffZ, intensity
};

constant float HY = 0.36;     // 地平線の画面上の高さ（下から）
constant float CAM_H = 0.6;   // 目の高さ
constant float CLOUD_H = 6.0; // 雲の高さ

float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + float2(1, 0)), u.x),
               mix(hash12(i + float2(0, 1)), hash12(i + float2(1, 1)), u.x), u.y);
}
float fbm(float2 p, int oct) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < oct; i++) {
        v += a * noise(p);
        p = float2(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6) + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

float airmass(float cz) { cz = max(cz, 0.0); return 1.0 / (cz + 0.025 * exp(-11.0 * cz)); }

constant float3 BR = float3(0.0058, 0.0135, 0.0331) * 9.0;
constant float BM = 0.021;
constant float3 BO = float3(0.017, 0.05, 0.0023); // オゾン吸収（夕方の空を青紫に）

float3 sunTransmittance(float3 s) {
    return exp(-(BR + BM + BO) * airmass(s.y + 0.06));
}

// 単純化した大気散乱
float3 atmo(float3 d, float3 s, float I) {
    float mu = dot(d, s);
    float3 tS = sunTransmittance(s);
    float3 tV = exp(-(BR + BM) * airmass(d.y));
    tV = mix(tV, float3(1.0), 0.0);
    float phR = 0.75 * (1.0 + mu * mu);
    float g = 0.8;
    float phM = 0.12 * (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);
    float3 sc = (BR * phR + BM * phM) / (BR + BM);
    float fade = smoothstep(-0.28, 0.02, s.y);
    return I * fade * tS * sc * (1.0 - tV);
}

float3 skyAt(float3 d, constant U& u) {
    float3 c = atmo(d, u.sun.xyz, u.sun.w);
    c += atmo(d, u.moon.xyz, 0.035) * u.moon.w * float3(0.75, 0.85, 1.1);
    c += float3(0.004, 0.007, 0.018) * (1.0 - smoothstep(-0.2, 0.1, u.sun.y));
    return c;
}

float cloudDensity(float2 xz, constant U& u) {
    float cov = u.w1.x;
    float2 p = xz * 0.09 + u.misc.yz;
    float n = fbm(p, 5);
    float n2 = fbm(p * 3.1 + 4.0, 3);
    n = n * 0.8 + n2 * 0.2;
    return smoothstep(1.0 - cov * 0.9 - 0.15, 1.0 - cov * 0.9 + 0.3, n + cov * 0.12);
}

float3 tonemap(float3 c, float exposure) {
    c = 1.0 - exp(-c * exposure);
    return pow(c, float3(1.0 / 1.1));
}

float3 lightColor(constant U& u) {
    float3 sunL = u.sun.w * sunTransmittance(u.sun.xyz) * smoothstep(-0.05, 0.1, u.sun.y);
    float3 moonL = float3(0.05, 0.065, 0.11) * u.moon.w * smoothstep(-0.05, 0.15, u.moon.y);
    return (sunL + moonL) * (1.0 - u.w1.x * 0.55 - u.w1.y * 0.2);
}

float3 ambientColor(constant U& u) {
    float3 up = skyAt(float3(0, 1, 0), u);
    float3 hor = skyAt(normalize(float3(0, 0.05, 1)), u);
    float over = u.w1.x;
    return mix(up * 0.9, (up + hor) * 0.6, over) + float3(0.012, 0.016, 0.03);
}

float3 snowTint(float3 c, float k) { return mix(c, float3(0.85, 0.88, 0.93), k); }

// ---- 背景（空・雲・丘・地面）----
struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut skyVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0, 1);
    o.uv = p;
    return o;
}

fragment float4 skyFragment(VOut in [[stage_in]], constant U& u [[buffer(0)]]) {
    float aspect = u.rt.w;
    float time = u.rt.z;
    float2 uv = in.uv;
    float3 d = normalize(float3((uv.x - 0.5) * aspect, uv.y - HY, 1.0));
    float3 s = u.sun.xyz;
    float cloud = u.w1.x, rain = u.w1.y, snow = u.w1.z, fog = u.w1.w;
    float flash = u.w2.x, sg = u.w2.z;
    float haze = clamp(fog * 0.85 + rain * 0.35 + snow * 0.15, 0.0, 1.0);

    float3 L = lightColor(u);
    float3 A = ambientColor(u);
    float3 horizonCol = skyAt(normalize(float3(d.x, 0.03, 1.0)), u);
    float3 overcast = (A + L * 0.25) * float3(0.95, 0.97, 1.0);
    horizonCol = mix(horizonCol, overcast * 1.2, clamp(cloud * 0.6 + haze * 0.5, 0.0, 1.0));

    float3 col;
    float az = d.x / d.z;
    float hill1 = 0.03 + 0.05 * fbm(float2(az * 1.7 + 3.0, 0.5), 4);
    float hill2 = 0.006 + 0.022 * fbm(float2(az * 3.1 + 11.0, 2.5), 4);

    if (d.y > 0.0 && d.y > hill1) {
        // 空
        col = skyAt(d, u);
        col = mix(col, overcast * mix(1.25, 0.8, d.y), clamp(cloud * cloud * 0.85 + rain * 0.2, 0.0, 0.95));

        // 星
        float night = 1.0 - smoothstep(-0.2, 0.0, s.y);
        if (night > 0.0) {
            float2 g = floor(float2(az, d.y / d.z) * 220.0);
            float h = hash12(g);
            float tw = 0.6 + 0.4 * sin(time * 2.0 + h * 40.0);
            col += float3(0.9, 0.95, 1.0) * step(0.9975, h) * night * tw * 0.6 * (1.0 - cloud) * (1.0 - fog);
        }

        // 太陽・月（うっすら）
        float show = u.misc.x;
        float mu = dot(d, s);
        float3 tS = sunTransmittance(s);
        float sunDisk = smoothstep(0.99988, 0.99994, mu) * 3.0 + pow(max(mu, 0.0), 1400.0) * 0.5;
        float3 sunC = tS * u.sun.w * sunDisk * show * smoothstep(-0.03, 0.02, s.y);
        float mm = dot(d, u.moon.xyz);
        float moonDisk = smoothstep(0.99975, 0.99985, mm);
        // 欠け
        float3 mOff = normalize(u.moon.xyz + float3(0.004, 0.002, 0));
        moonDisk *= 1.0 - smoothstep(0.99975, 0.99985, dot(d, mOff)) * 0.85;
        float3 moonC = float3(0.55, 0.58, 0.62) * (moonDisk + pow(max(mm, 0.0), 2000.0) * 0.1) * u.moon.w * show;

        // 雲（平面に投影したボリューム風の雲）
        float t = CLOUD_H / max(d.y, 0.01);
        float2 cp = d.xz * t;
        float dens = cloudDensity(cp, u);
        float alpha = 0.0;
        if (dens > 0.001) {
            float dl = cloudDensity(cp + s.xz * 1.6, u);
            float shadow = exp(-dl * 2.4);
            float phase = 1.0 + 1.6 * pow(max(mu, 0.0), 6.0);
            float3 cc = L * (0.25 + 1.1 * shadow) * phase + A * 0.85;
            cc *= mix(1.0, 0.55, rain * 0.8 + u.w1.x * 0.15);
            cc += float3(0.7, 0.75, 0.95) * flash * 1.8;
            alpha = dens * smoothstep(0.0, 0.08, d.y);
            float far = 1.0 - exp(-t * 0.012);
            cc = mix(cc, horizonCol, far * 0.85);
            col = mix(col, cc, alpha);
        }
        col += (sunC + moonC) * (1.0 - alpha) * (1.0 - haze * 0.8);
        // 地平線付近のかすみ
        col = mix(col, horizonCol, (1.0 - smoothstep(0.0, 0.25, d.y)) * haze * 0.8);
        col += float3(0.5, 0.55, 0.7) * flash * 0.25;
    } else if (d.y > 0.0) {
        // 遠景の丘
        bool near = d.y < hill2;
        float3 base = near ? float3(0.05, 0.09, 0.035) : float3(0.06, 0.08, 0.07);
        float tex = fbm(float2(az * 40.0, d.y * 300.0), 3);
        base *= 0.8 + 0.4 * tex;
        base = snowTint(base, sg * 0.85);
        float3 c = base * (L * max(s.y, 0.0) * 0.8 + A * 1.2);
        float aerial = near ? 0.22 : 0.45;
        aerial = clamp(aerial + haze * 0.3, 0.0, 0.98);
        col = mix(c, horizonCol, aerial);
    } else {
        // 地面
        float t = CAM_H / max(-d.y, 0.0005);
        float2 p = d.xz * t;
        float big = fbm(p * 0.35, 4);
        float fine = fbm(p * 6.0, 3);
        float detail = mix(fine, 0.5, smoothstep(4.0, 25.0, t));
        float3 g1 = float3(0.06, 0.13, 0.03), g2 = float3(0.16, 0.22, 0.06);
        float3 base = mix(g1, g2, big * 0.8 + detail * 0.4);
        // 雪
        float sm = smoothstep(1.0 - sg - 0.15, 1.0 - sg + 0.15, fbm(p * 1.3 + 7.0, 3) * 0.7 + 0.3 * detail);
        base = snowTint(base, sm * clamp(sg * 1.3, 0.0, 1.0));
        base *= mix(1.0, 0.7, rain);  // 濡れ
        // 雲の影
        float shadow = 1.0;
        if (s.y > 0.02) {
            float2 cpt = p + s.xz / s.y * CLOUD_H;
            shadow = 1.0 - cloudDensity(cpt, u) * 0.75;
        }
        float3 c = base * (L * max(s.y, 0.0) * 1.6 * shadow + A * 1.3);
        c += float3(0.5, 0.55, 0.7) * flash * 0.08;
        float fd = 0.012 + fog * 0.35 + rain * 0.06 + snow * 0.03;
        col = mix(c, horizonCol * mix(0.5, 0.95, haze), 1.0 - exp(-t * fd));
    }

    col = tonemap(col, u.w2.w);
    return float4(col, 1.0);
}

// ---- 草（インスタンス描画）----
struct GOut { float4 pos [[position]]; float3 color; };

vertex GOut grassVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        constant U& u [[buffer(0)]], constant uint& count [[buffer(1)]]) {
    float aspect = u.rt.w, time = u.rt.z;
    float3 s = u.sun.xyz;
    float wind = u.w2.y, sg = u.w2.z;
    float id = float(iid);
    float r1 = hash12(float2(id, 1.3)), r2 = hash12(float2(id, 7.1));
    float r3 = hash12(float2(id, 3.7)), r4 = hash12(float2(id, 9.9));

    // 奥 → 手前の順に並べる（対数分布）
    float zmin = 1.25, zmax = 28.0;
    float k = (id + r4) / float(count);
    float z = zmax * pow(zmin / zmax, k);
    float x = (r1 - 0.5) * z * aspect * 1.15;

    float h = (0.07 + 0.13 * r2 * r2) * (1.0 - 0.55 * sg);
    float w = 0.0035 + 0.0035 * r3;

    uint seg = vid / 2;
    float side = (vid == 6) ? 0.0 : ((vid % 2 == 0) ? -1.0 : 1.0);
    float t = (vid == 6) ? 1.0 : float(seg) / 3.0;

    float gust = sin(time * 1.3 + x * 1.7 + z * 0.9) * 0.6 + sin(time * 2.9 + x * 4.0 + r3 * 6.0) * 0.25
               + (fbm(float2(x * 0.6 - time * (0.3 + abs(wind)), z * 0.6), 2) - 0.5) * 1.2;
    float sway = 0.12 + abs(wind) * 0.7 * (0.4 + 0.6 * u.misc.w);
    float lean = (r1 - 0.5) * 0.6 + (r4 - 0.5) * 0.4;
    float bend = lean + wind * 0.9 + gust * sway;
    float ox = bend * t * t * h * 0.7;
    float oy = h * t * (1.0 - 0.25 * bend * bend);
    float width = w * (1.0 - t * 0.92) * side;

    float3 wp = float3(x + ox + width, -CAM_H + oy, z);
    float2 suv = float2(wp.x / wp.z / aspect + 0.5, wp.y / wp.z + HY);

    // 色
    float3 base = mix(float3(0.025, 0.06, 0.012), float3(0.2, 0.28, 0.06), t);
    base = mix(base, float3(0.3, 0.3, 0.08) * t, r3 * 0.35);
    base = snowTint(base, sg * t * t * 0.8);
    base *= mix(1.0, 0.75, u.w1.y);

    float3 L = lightColor(u);
    float3 A = ambientColor(u);
    float shadow = 1.0;
    if (s.y > 0.02) shadow = 1.0 - cloudDensity(float2(x, z) + s.xz / s.y * CLOUD_H, u) * 0.75;
    float back = pow(max(s.z, 0.0), 2.0) * (1.0 - smoothstep(0.0, 0.5, s.y)); // 逆光で透ける
    float3 c = base * (L * (max(s.y, 0.0) * 1.4 + back * t * 1.2) * shadow + A * 1.2);
    c += float3(0.5, 0.55, 0.7) * u.w2.x * 0.06;

    float3 horizonCol = skyAt(normalize(float3(x / z, 0.03, 1.0)), u);
    float3 overcast = (A + L * 0.25);
    float haze = clamp(u.w1.w * 0.85 + u.w1.y * 0.35 + u.w1.z * 0.15, 0.0, 1.0);
    horizonCol = mix(horizonCol, overcast * 1.2, clamp(u.w1.x * 0.6 + haze * 0.5, 0.0, 1.0));
    float fd = 0.012 + u.w1.w * 0.35 + u.w1.y * 0.06 + u.w1.z * 0.03;
    c = mix(c, horizonCol * mix(0.5, 0.95, haze), 1.0 - exp(-z * fd));

    GOut o;
    o.pos = float4(suv * 2.0 - 1.0, 0, 1);
    o.color = tonemap(c, u.w2.w);
    return o;
}

fragment float4 grassFragment(GOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}
"""#
