#pragma once

#include <owl/owl.h>
#include <owl/common/math/vec.h>
#include <owl/common/math/random.h>
#include "../../common/src/material.h"
#include "../../common/src/light.h"

struct Photon {
    owl::vec3f pos;
    owl::vec3f dir;
    int power;
    owl::vec3f color;
    bool is_alive;
};

/* variables for the ray generation program */
struct RayGenData
{
    uint32_t *fbPtr;
    owl::vec2i  fbSize;
    OptixTraversableHandle world;
    owl::vec3f sky_color;

    LightSource* lights;
    int numLights;

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
    owl::vec3f  sky_color;
};

