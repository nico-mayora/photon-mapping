#pragma once
#include <vector>

#include "owl/common/math/vec.h"
#include "owl/owl.h"
#include "mesh.h"

/* This holds all the state required for the path tracer to function.
 * As we use the STL, this is code in C++ land that needs a bit of
 * glue to transform to data that can be held in the GPU.
 */
struct World {
    std::vector<LightSource> light_sources;
    std::vector<Mesh> meshes;
};

struct GeometryData {
    std::vector<OWLGeom> geometry;
    OWLGeomType trianglesGeomType;
    OWLGroup trianglesGroup;
    OWLGroup worldGroup;
};

GeometryData loadGeometry(OWLContext &owlContext, const std::unique_ptr<World> &world);