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

    std::unique_ptr<World> world;

    GeometryData geometryData;

    OWLBuffer photonsBuffer;
    OWLBuffer photonsCount;
    OWLBuffer causticsPhotonsBuffer;
    OWLBuffer causticsPhotonsCount;

    int maxDepth;
    int maxPhotons;
    int maxCausticsPhotons;
    int photonsPerWatt;
    int causticsPhotonsPerWatt;
};