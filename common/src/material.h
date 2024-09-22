#pragma once
#include "owl/common/math/vec.h"

/* We store the MaterialType to correctly pick the BSDF when reflecting incident rays. */
enum MaterialType {
    LAMBERTIAN,
    SPECULAR,
    GLASS,
};

struct Material {
    MaterialType surface_type;
    owl::vec3f albedo;
    double reflectivity; // higher = more reflective
    double refraction_idx;
};

