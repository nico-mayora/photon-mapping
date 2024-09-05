#pragma once
#include "owl/common/math/vec.h"

/* We store the MaterialType to correctly pick the BSDF when reflecting the rays. */
enum MaterialType {
    LAMBERTIAN,
    SPECULAR,
    GLASS,
};

struct Material {
    MaterialType surface_type;
    owl::vec3f albedo;
    double specular_roughness;
    double refraction_idx;
};