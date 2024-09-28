#pragma once

#include "owl/common/math/vec.h"
#include <owl/common/math/random.h>

typedef owl::LCG<> Random;

enum RayEvent {
    Missed = 0,
    Absorbed = 1,
    ReflectedDiffuse = 2,
    ReflectedSpecular = 4,
    Refraction = 8,
};

struct PerRayData {
    Random random;
    owl::vec3f colour;
    RayEvent event;
    struct {
        owl::vec3f s_origin;
        owl::vec3f s_direction;
        owl::vec3f normal_at_hitpoint;
    } scattered;
    struct {
        double diffuseCoefficient;
        double reflectivity;
        double refraction_idx;
    } material;
};