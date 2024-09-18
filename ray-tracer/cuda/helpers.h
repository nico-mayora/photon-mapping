#pragma once

#include "deviceCode.h"

#define RANDVEC3F owl::vec3f(rnd(),rnd(),rnd())
#define EPS 1e-3f

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

inline __device__ owl::vec3f getPrimitiveNormal(const TrianglesGeomData& self) {
    using namespace owl;
    const unsigned int primID = optixGetPrimitiveIndex();
    const vec3i index  = self.index[primID];
    const vec3f &A     = self.vertex[index.x];
    const vec3f &B     = self.vertex[index.y];
    const vec3f &C     = self.vertex[index.z];

    return normalize(cross(B-A,C-A));
}


inline __device__ void scatterLambertian(PerRayData& prd, const TrianglesGeomData& self) {
    using namespace owl;

    vec3f Ng = getPrimitiveNormal(self);

    // scatter ray:
    const vec3f rayDir = optixGetWorldRayDirection();
    const vec3f rayOrg = optixGetWorldRayOrigin();

    if (dot(Ng,rayDir)  > 0.f) // If both dir and normal have the same direction...
        Ng = -Ng; // ...flip normal...
    Ng = normalize(Ng); // ...and renormalise just in case.

    auto scatter_direction = Ng + normalize(randomPointInUnitSphere(prd.random));

    if (dot(scatter_direction, scatter_direction) < EPS) {
        scatter_direction = Ng;
    }

    prd.scattered.s_direction = scatter_direction;
    const auto tmax = optixGetRayTmax();

    prd.scattered.s_origin = rayOrg + tmax * rayDir;

    const auto &material = *self.material;

    prd.event = Scattered;
    prd.colour = material.albedo;
}

inline __device__ void scatterSpecular(PerRayData& prd, const TrianglesGeomData& self) {
    using namespace owl;
    const vec3f rayDir = optixGetWorldRayDirection();
    const vec3f rayOrg = optixGetWorldRayOrigin();
    const auto tmax = optixGetRayTmax();

    const auto material = *self.material;
    const auto normal = getPrimitiveNormal(self);

    const auto reflected = reflect(normalize(rayDir), normal);

    const auto fuzzed = reflected +
        randomPointInUnitSphere(prd.random) * static_cast<float>(1 - material.reflectivity);

    if (dot(fuzzed, normal) > 0.f) {
        prd.event = Scattered;
        prd.scattered.s_direction = fuzzed;
        prd.scattered.s_origin = rayOrg + tmax * rayDir;
    } else {
        prd.event = Absorbed;
    }
}

inline __device__ double schlickReflectance(const double cos, const double ior) {
    auto r0 = (1. - ior) / (1. + ior);
    r0 = r0 * r0;
    return r0 + (1. - r0) * pow(1. - cos, 5);
}

inline __device__ owl::vec3f refract(const owl::vec3f &u, const owl::vec3f &v, const float ratio) {
    const auto cos_theta = min(dot(-u, v), 1.f);
    const auto r_out_perp = ratio * (u + cos_theta * v);
    const auto r_out_parallel = -sqrt(abs(1.f - dot(r_out_perp, r_out_perp))) * v;
    return r_out_perp + r_out_parallel;
}

inline __device__ void scatterGlass(PerRayData& prd, const TrianglesGeomData& self) {
    using namespace owl;

    const vec3f rayDir = optixGetWorldRayDirection();
    const vec3f rayOrg = optixGetWorldRayOrigin();
    const auto tmax = optixGetRayTmax();

    const auto unit_dir = normalize(rayDir);
    const auto material = *self.material;

    const vec3f normal = getPrimitiveNormal(self);
    // if the dot is positive, we're hitting the triangle's from behind
    const double refraction_ratio = (dot(rayDir, normal) > 0.)
                                        ? 1 / material.refraction_idx
                                        : material.refraction_idx;

    const auto cos_theta = min(dot(-unit_dir, normal), 1.);
    const auto sin_theta = sqrt(1. - cos_theta * cos_theta);

    const auto cannot_refract = refraction_ratio * sin_theta > 1.;

    vec3f direction;
    if (cannot_refract || schlickReflectance(cos_theta, refraction_ratio) > prd.random()) {
        direction = reflect(unit_dir, normal);
    } else {
        direction = refract(unit_dir, normal, refraction_ratio);
    }

    prd.event = Scattered;
    prd.scattered.s_origin = rayOrg + tmax * rayDir;
    prd.scattered.s_direction = direction;
    prd.colour = material.albedo;
}