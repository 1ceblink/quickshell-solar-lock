// The look of gravitational lensing around the black hole, on a square that always faces the camera (UV0 = 0..1).
// Light from the far side of the disk is bent over and under the hole, and a thin bright photon ring hugs the shadow.
// `q` is the distance from the centre in units of the event horizon's radius. Added on top of the scene.
float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void MAIN()
{
    vec2 p = (UV0 - 0.5) * 2.0 * halfSize;       // scene units from the centre
    vec2 c = vec2(p.x * cos(roll) + p.y * sin(roll), -p.x * sin(roll) + p.y * cos(roll));   // follow the disk's tilt on screen
    float q = length(c) / horizon;
    float up = c.y / max(length(c), 0.0001);     // +1 straight above the hole, -1 straight below
    float side = c.x / max(length(c), 0.0001);   // +1 on the right

    float shadow = smoothstep(0.97, 1.0, q);                           // nothing inside the event horizon
    float photon = exp(-pow((q - 1.07) / 0.045, 2.0));                 // thin, bright photon ring
    float arcTop = exp(-pow((q - 1.45) / 0.34, 2.0)) * smoothstep(0.1, 0.8, up);
    float arcBottom = 0.45 * exp(-pow((q - 1.28) / 0.22, 2.0)) * smoothstep(0.2, 0.9, -up);
    float haze = 0.16 * exp(-(q - 1.0) / 1.5) * (1.0 - smoothstep(3.0, 5.0, q));
    float grain = 0.75 + 0.5 * vnoise(vec2(atan(c.y, c.x) * 9.0, q * 6.0 - t * 0.6));
    float beam = 0.55 + 0.75 * (0.5 + 0.5 * side * dopplerSign);       // the approaching side is brighter

    float v = shadow * (photon * 1.6 + (arcTop + arcBottom) * 1.1 * grain + haze) * beam;
    v *= 1.0 - smoothstep(0.85, 1.0, length(UV0 - 0.5) * 2.0);          // fade out before the edge of the square

    vec3 hot = mix(vec3(1.0, 0.55, 0.18), vec3(1.0, 0.93, 0.8), clamp(photon + arcTop * 0.6, 0.0, 1.0));
    BASE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    SPECULAR_AMOUNT = 0.0;
    ROUGHNESS = 1.0;
    EMISSIVE_COLOR = hot * v * gain;
}
