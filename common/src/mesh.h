#pragma once

#include <vector>
#include "owl/common/math/vec.h"

struct Material {
    owl::vec3f albedo;
    float diffuse;
    float specular;
    float transmission;
    float refraction_idx;
};

enum LightType {
    POINT_LIGHT,
    SQUARE_LIGHT,
};

struct LightSource {
    LightType source_type;
    owl::vec3f pos;
    double power;
    owl::vec3f rgb;
    /* for emission surface */
    owl::vec3f normal;
    double side_length;

    /* calculated values */
    int num_photons;
};

/* variables for the triangle mesh geometry */
struct TrianglesGeomData
{
    Material *material;
    owl::vec3i *index;
    owl::vec3f *vertex;
};

/* The vectors need to be (trivially) transformed into regular arrays
   before being passed into OptiX */
struct Mesh {
    std::string name;
    std::vector<owl::vec3f> vertices;
    std::vector<owl::vec3i> indices;
    std::shared_ptr<Material> material;
};

