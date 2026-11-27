// A relativistic jet from the black hole, on a tall square that always faces the camera (UV0.y runs from the hole, 0,
// to the far tip, 1). A thin, white-hot core inside a wider blue sheath that opens up with distance, with knots of
// brighter plasma travelling outward. Added on top of the scene.
float hash(float n)
{
    return fract(sin(n * 12.9898) * 43758.5453);
}

float vnoise(float x)
{
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash(i), hash(i + 1.0), f);
}

void MAIN()
{
    float s = UV0.y;
    float x = (UV0.x - 0.5) * 2.0;
    float w = 0.16 + 0.62 * pow(s, 0.8);                        // the beam opens up with distance
    float core = exp(-pow(x / (w * 0.3), 2.0));
    float sheath = exp(-pow(x / w, 2.0)) * 0.55;
    float halo = exp(-pow(x / (w * 2.0), 2.0)) * 0.2;
    float knots = 0.55 + 0.9 * vnoise(s * 11.0 - t * 2.6) + 0.35 * vnoise(s * 27.0 - t * 4.1 + 5.0);
    float fade = pow(1.0 - s, 1.4) * smoothstep(0.0, 0.18, s);

    float v = (core * 1.1 + sheath + halo) * knots * fade;
    vec3 col = mix(vec3(0.35, 0.55, 1.0), vec3(0.88, 0.95, 1.0), clamp(core * 1.2, 0.0, 1.0));
    BASE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    SPECULAR_AMOUNT = 0.0;
    ROUGHNESS = 1.0;
    EMISSIVE_COLOR = col * v * gain;
}
