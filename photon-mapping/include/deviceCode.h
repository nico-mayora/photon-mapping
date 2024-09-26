#pragma once

#include "owl/include/owl/owl.h"
#include "owl/include/owl/common/math/vec.h"
#include "owl/include/owl/common/math/random.h"
#include "../../common/src/material.h"
#include "../../common/src/light.h"
#include "photon.h"

#define MAX_RAY_BOUNCES 200
#define MAX_PHOTONS 100000

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

