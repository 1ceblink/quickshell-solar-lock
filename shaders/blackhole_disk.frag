// Accretion disk of the black hole, drawn on a flat square (UV0 = 0..1, the disk is centred).
// Hot gas spirals at a Keplerian speed (fast near the hole, slow outside), streaked by noise that wraps seamlessly
// around the ring. The side moving toward the camera is brighter (Doppler beaming). Added on top of the scene.
float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// value noise that repeats every `per` cells along y, so it joins up around the ring
float pnoise(vec2 p, float per)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float y0 = mod(i.y, per);
    float y1 = mod(i.y + 1.0, per);
    return mix(mix(hash(vec2(i.x, y0)), hash(vec2(i.x + 1.0, y0)), f.x),
               mix(hash(vec2(i.x, y1)), hash(vec2(i.x + 1.0, y1)), f.x), f.y);
}

float fbm(vec2 p, float per)
{
    float v = 0.0;
    float a = 0.55;
    for (int k = 0; k < 4; k++) {
        v += a * pnoise(p, per);
        p *= 2.03;
        per *= 2.0;
        a *= 0.5;
    }
    return v;
}

vec3 heat(float x)   // 0 = outer edge, 1 = inner edge
{
    vec3 outer = vec3(0.55, 0.10, 0.04);
    vec3 mid = vec3(1.0, 0.48, 0.14);
    vec3 inner = vec3(1.0, 0.93, 0.80);
    return x < 0.55 ? mix(outer, mid, x / 0.55) : mix(mid, inner, (x - 0.55) / 0.45);
}

void MAIN()
{
    vec2 p = (UV0 - 0.5) * 2.0;
    float r = length(p);
    float phi = atan(p.y, p.x);
    float x = clamp((r - rin) / (1.0 - rin), 0.0, 1.0);          // 0 at the inner edge, 1 at the outer edge

    float omega = 1.6 / pow(max(r, 0.08) * 4.0, 1.5);              // Keplerian: angular speed falls off as r^-1.5
    float a = phi - t * omega;
    float u = a / 6.2831853 + 0.5;                                  // 0..1 around the ring
    float n = fbm(vec2(r * 22.0, u * 12.0), 12.0);                  // streaks: stretched along the orbit
    float swirl = fbm(vec2(r * 7.0 + 3.0, u * 6.0 + r * 3.0), 6.0);

    float inner = smoothstep(rin, rin + 0.05, r);                   // soft inner edge
    float outer = 1.0 - smoothstep(0.78, 1.0, r);                   // soft outer edge
    float temp = pow(1.0 - x, 1.9);                                 // hotter toward the hole
    float dens = 0.35 + 1.05 * n + 0.45 * swirl;
    float beam = 0.30 + 1.15 * (0.5 + 0.5 * sin(phi - phi0));       // Doppler: one side brighter
    float v = inner * outer * (0.12 + temp * 1.5) * dens * beam;

    BASE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    SPECULAR_AMOUNT = 0.0;
    ROUGHNESS = 1.0;
    EMISSIVE_COLOR = heat(clamp(temp + 0.25 * n, 0.0, 1.0)) * v * gain;
}
