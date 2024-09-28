#pragma once

#include "owl/include/owl/owl.h"
#include "owl/include/owl/common/math/vec.h"
#include "owl/include/owl/common/math/random.h"
#include "../../common/src/material.h"
#include "../../common/src/light.h"
#include "photon.h"
#include "../../common/src/ray.h"

#define MAX_RAY_BOUNCES 200
#define MAX_PHOTONS 100000

struct PhotonMapperRGD
{
    Photon *photons;
    int *photonsCount;
    owl::vec2i dims;
    OptixTraversableHandle world;
};

struct PointLightRGD: public PhotonMapperRGD
{
    owl::vec3f position;
    owl::vec3f color;
    float intensity;
};

struct PhotonMapperPRD
{
    owl::LCG<> random;
    owl::vec3f color;
    RayEvent event;
    struct {
        owl::vec3f origin;
        owl::vec3f direction;
    } scattered;
};
