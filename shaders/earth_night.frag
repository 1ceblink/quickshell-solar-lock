// City lights for Earth: added on top of the planet, and only where the Sun does not shine.
void MAIN()
{
    float lit = dot(normalize(NORMAL), sunDir);        // > 0 on the day side, < 0 at night
    float night = smoothstep(0.08, -0.22, lit);        // soft edge along the terminator
    vec3 lights = texture(nightMap, UV0).rgb;
    BASE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    SPECULAR_AMOUNT = 0.0;
    ROUGHNESS = 1.0;
    EMISSIVE_COLOR = lights * night * brightness;
}
