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

    GeometryData geometryData;

    OWLBuffer photonsBuffer;
    OWLBuffer photonsCount;

    int maxDepth;
};