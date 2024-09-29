#pragma once

#include "owl/common/math/vec.h"
#include <owl/common/math/random.h>

typedef owl::LCG<> Random;

enum RayEvent {
    Refraction,
    ReflectedSpecular,
    ReflectedDiffuse,
    Absorbed,
    Missed,
};