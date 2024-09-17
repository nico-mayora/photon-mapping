#pragma once

#include "deviceCode.h"

#define RANDVEC3F owl::vec3f(rnd(),rnd(),rnd())

inline __device__ owl::vec3f randomPointInUnitSphere(Random &rnd) {
    owl::vec3f p;
    do {
        p = 2.0f*RANDVEC3F - owl::vec3f(1, 1, 1);
    } while (dot(p,p) >= 1.0f);
    return p;
}

inline __device__ owl::vec3f scatterLambertian(Random &rnd) { return owl::vec3f(0.); }