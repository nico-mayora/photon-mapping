#pragma once

#include <owl/owl.h>
#include <owl/common/math/vec.h>
#include <owl/common/math/random.h>
#include "../../common/src/mesh.h"

#define MAX_RAY_BOUNCES 5
#define MAX_PHOTONS 100000

typedef owl::LCG<> Random;

struct Photon
{
    owl::vec3f pos;
    owl::vec3f dir;
    int power;
    owl::vec3f color;
    bool is_alive;
};

/* variables for the ray generation program */
struct RayGenData
{
    Photon *photons;
    int photonsCount;
    OptixTraversableHandle world;
    int lightsNum;
    LightSource *lightSources;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_color;
};

struct PerRayData {
    Random random;
    owl::vec3f colour;
//    RayEvent event;
    bool debug;

    struct {
        owl::vec3f origin;
        owl::vec3f direction;
        owl::vec3f normal;
        float distance;
    } hit_point;

    Material material;
};