#pragma once

#include "owl/common/math/vec.h"
#include <owl/common/math/random.h>

typedef owl::LCG<> Random;

enum RayEvent {
    Scattered,
    Absorbed,
    Missed,
};

struct PerRayData {
    Random random;
    int bounces_ramaining;

    owl::vec3f colour;
    RayEvent event;
    struct {
        owl::vec3f s_origin;
        owl::vec3f s_direction;
        owl::vec3f normal_at_hitpoint;
    } scattered;
};