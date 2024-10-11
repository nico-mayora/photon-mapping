#pragma once
#include <vector>

#include "owl/common/math/vec.h"
#include "owl/owl.h"
#include "mesh.h"


struct LightSource {
    owl::vec3f pos;
    double power;
    owl::vec3f rgb;
    /* for emission surface */
    owl::vec3f normal;
    double side_length;

    /* calculated values */
    int num_photons;
};

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