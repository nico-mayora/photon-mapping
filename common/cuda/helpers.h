#pragma once

#include "../src/ray.h"
#include "../src/mesh.h"

#define RANDVEC3F owl::vec3f(rnd(),rnd(),rnd())
#define EPS 1e-3f
#define DIFFUSE_COEF 1.f

inline __device__ owl::vec3f clampvec(owl::vec3f v, float f) {
    return owl::vec3f(owl::clamp(v.x, f), owl::clamp(v.y, f), owl::clamp(v.z, f));
}

inline __device__ float norm(owl::vec3f v) {
    return sqrtf(dot(v, v));
}

inline __device__ owl::vec3f randomPointInUnitSphere(Random &rnd) {
    owl::vec3f p;
    do {
        p = 2.0f*RANDVEC3F - owl::vec3f(1, 1, 1);
    } while (dot(p,p) >= 1.0f);
    return p;
}

inline __device__ owl::vec3f reflect(const owl::vec3f &u, const owl::vec3f &v) {
    return u - 2 * dot(u, v) * v;
}

inline __device__
bool refract(const owl::vec3f& v,
             const owl::vec3f& n,
             const float ni_over_nt,
             owl::vec3f &refracted)
{
    const owl::vec3f uv = normalize(v);
    const float dt = dot(uv, n);
    const float discriminant = 1.0f - ni_over_nt * ni_over_nt*(1 - dt * dt);
    if (discriminant > 0.f) {
        refracted = ni_over_nt * (uv - n * dt) - n * sqrtf(discriminant);
        return true;
    }

    return false;
}

inline __device__ owl::vec3f getPrimitiveNormal(const TrianglesGeomData& self) {
    using namespace owl;
    const unsigned int primID = optixGetPrimitiveIndex();
    const vec3i index  = self.index[primID];
    const vec3f &A     = self.vertex[index.x];
    const vec3f &B     = self.vertex[index.y];
    const vec3f &C     = self.vertex[index.z];

    return normalize(cross(B-A,C-A));
}

inline __device__ float schlickFresnelAprox(const float cos, const float ior) {
  float r0 = (1. - ior) / (1. + ior);
  r0 = r0 * r0;
  return r0 + (1. - r0) * pow(1. - cos, 5);
}