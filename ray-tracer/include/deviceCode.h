#pragma once

#include "owl/include/owl/owl.h"
#include "owl/include/owl/common/math/vec.h"
#include "owl/include/owl/common/math/random.h"
#include "photon.h"
#include "../../common/src/camera.h"

/* variables for the ray generation program */
struct RayGenData
{
    uint32_t *fbPtr;
    owl::vec2i  fbSize;
    OptixTraversableHandle world;

    LightSource* lights;
    int numLights;
    Photon* photons;
    int numPhotons;

    int samples_per_pixel;
    int max_ray_depth;

    struct {
        owl::vec3f pos;
        owl::vec3f dir_00; // out-of-screen
        owl::vec3f dir_du; // left-to-right
        owl::vec3f dir_dv; // bottom-to-top
    } camera;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_colour;
};

typedef owl::LCG<> Random;

struct PerRayData {
    Random random;
    owl::vec3f colour;
    owl::vec3f hit_point;

    struct {
        owl::Ray ray;
        owl::vec3f normal_at_hitpoint;
    } scattered;

    float attenuation;
};

