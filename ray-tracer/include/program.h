#pragma once

#include "owl/owl.h"
#include "../../common/src/camera.h"
#include "photon.h"
#include "../../common/src/world.h"
#include "owl/common/math/vec.h"
#include "glm/glm.hpp"

struct Program {
    OWLContext owlContext;
    OWLModule owlModule;
    OWLRayGen rayGen;

    OWLBuffer frameBuffer;
    owl::vec2i frameBufferSize;

    GeometryData geometryData;

    Photon* globalPhotons;
    int numGlobalPhotons;
    Photon* causticPhotons;
    int numCausticPhotons;

    OWLBuffer lightsBuffer;
    int numLights;

    int samplesPerPixel;
    int maxDepth;

    Camera camera;
};