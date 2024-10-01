#pragma once

#include "owl/include/owl/owl.h"
#include "owl/include/owl/common/math/vec.h"
#include "owl/include/owl/common/math/random.h"
#include "photon.h"
#include "../../common/src/camera.h"

/* variables for the ray generation program */
struct PhotonViewerRGD
{
    uint32_t *frameBuffer;
    owl::vec2i frameBufferSize;

    Photon* photons;
    int numPhotons;

    OptixTraversableHandle world;
    owl::vec3f cameraPos;
};

struct PhotonViewerPRD
{
    bool hit;
};