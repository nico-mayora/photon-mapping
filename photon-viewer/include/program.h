#pragma once

#include "owl/owl.h"
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

    OWLBuffer photonsBuffer;
    int numPhotons;

    struct {
        owl::vec3f lookAt;
        owl::vec3f lookFrom;
        owl::vec3f lookUp;
        float fovy;
    } camera;
};