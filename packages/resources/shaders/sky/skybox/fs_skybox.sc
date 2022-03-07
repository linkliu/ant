$input v_posWS

#include <bgfx_shader.sh>
#include "common/sphere_coord.sh"

#ifdef CUBEMAP_SKY
#undef CUBEMAP_SKY
#endif //CUBEMAP_SKY

#define CUBEMAP_SKY 1

#ifdef CUBEMAP_SKY
SAMPLERCUBE(s_skybox, 0);
#else //!CUBEMAP_SKY
SAMPLER2D(s_skybox, 0);
#endif //CUBEMAP_SKY

uniform vec4 u_skybox_param;
#define u_skybox_intensity u_skybox_param.x

void main()
{
#ifdef CUBEMAP_SKY
    vec3 n = normalize(v_posWS.xyz);
    vec4 color = textureCube(s_skybox, n);
#else //!CUBEMAP_SKY
    vec2 uv = dir2spherecoord(normalize(v_posWS.xyz));
    vec4 color = texture2D(s_skybox, uv);
#endif //CUBEMAP_SKY

    gl_FragColor = vec4(u_skybox_intensity * color.rgb, color.a);
    
}
