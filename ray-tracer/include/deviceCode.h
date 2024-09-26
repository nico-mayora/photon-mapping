#pragma once

#include "owl/include/owl/owl.h"
#include "owl/include/owl/common/math/vec.h"
#include "owl/include/owl/common/math/random.h"
#include "../../common/src/material.h"
#include "../../common/src/light.h"
#include "photon.h"
#include "../../common/src/camera.h"

/* variables for the ray generation program */
struct RayGenData
{
    uint32_t *fbPtr;
    owl::vec2i  fbSize;
    OptixTraversableHandle world;
    owl::vec3f sky_color;

    LightSource* lights;
    int numLights;
    Photon* photons;
    int numPhotons;

    Camera camera;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_color;
};

