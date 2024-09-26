#pragma once

#include "owl/include/owl/owl.h"
#include "../../common/src/camera.h"
#include "photon.h"

/* variables for the ray generation program */
struct PhotonViewerRGD
{
    uint32_t *frameBuffer;
    owl::vec2i frameBufferSize;

    Photon* photons;
    int numPhotons;

    OptixTraversableHandle world;
    Camera camera;
};

struct PhotonViewerPRD
{
    bool hit;
    owl::vec3f hitPoint;
};