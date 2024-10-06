#pragma once

#include "owl/owl.h"
#include "../../common/src/camera.h"
#include "photon.h"
#include "../../common/src/world.h"
#include "owl/common/math/vec.h"
#include <cukd/box.h>

struct Program {
    OWLContext owlContext;
    OWLModule owlModule;
    OWLRayGen rayGen;

    OWLBuffer frameBuffer;
    owl::vec2i frameBufferSize;

    GeometryData geometryData;

    Photon* globalPhotons;
    cukd::box_t<float3>* globalPhotonsBounds;
    int numGlobalPhotons;
    Photon* causticPhotons;
    cukd::box_t<float3>* causticPhotonsBounds;
    int numCausticPhotons;

    OWLBuffer lightsBuffer;
    int numLights;

    int samplesPerPixel;
    int maxDepth;

    Camera camera;
};