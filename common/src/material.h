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
    // Specular == Metal
    double reflectivity; // higher = more reflective
    // Glass
    double refraction_idx;
};

