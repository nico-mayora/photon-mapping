#pragma once

#include "owl/include/owl/owl.h"
#include "owl/include/owl/common/math/vec.h"
#include "owl/include/owl/common/math/random.h"
#include "photon.h"

struct PhotonMapperRGD
{
    Photon *photons;
    int *photonsCount;
    OptixTraversableHandle world;
    int maxDepth;
    bool causticsMode;
};

struct PointLightRGD: public PhotonMapperRGD
{
    owl::vec3f position;
    owl::vec3f color;
    float intensity;
};

enum RayEvent
{
    MISS = 0,
    ABSORBED = 1,
    SCATTER_DIFFUSE = 2,
    SCATTER_SPECULAR = 4,
    SCATTER_REFRACT = 8,
};

struct PhotonMapperPRD
{
    owl::LCG<> random;
    owl::vec3f color;
    RayEvent event;
    struct {
        owl::vec3f origin;
        owl::vec3f direction;
        owl::vec3f color;
    } scattered;
};
