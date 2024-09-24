#pragma once

#include <owl/owl.h>
#include <owl/common/math/vec.h>
#include <owl/common/math/random.h>
#include "../../common/src/material.h"
#include "../../common/src/light.h"

#define MAX_RAY_BOUNCES 200
#define MAX_PHOTONS 100000

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
    int *photonsCount;
    OptixTraversableHandle world;
    int lightsNum;
    LightSource *lightSources;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_color;
};

