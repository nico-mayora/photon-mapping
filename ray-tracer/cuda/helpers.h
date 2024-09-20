#pragma once

#include "deviceCode.h"

#define RANDVEC3F owl::vec3f(rnd(),rnd(),rnd())
#define EPS 1e-3f

inline __device__ owl::vec3f clampvec(owl::vec3f v, float f) {
    return owl::vec3f(owl::clamp(v.x, f), owl::clamp(v.y, f), owl::clamp(v.z, f));
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
    prd.scattered.normal_at_hitpoint = Ng;

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
        prd.scattered.s_direction = normalize(fuzzed);
        prd.scattered.s_origin = rayOrg + tmax * rayDir;
        prd.colour = material.albedo;
    } else {
        prd.event = Absorbed;
    }
}

inline __device__ float schlickReflectance(const float cos, const float ior) {
    float r0 = (1.f - ior) / (1. + ior);
    r0 = r0 * r0;
    return r0 + (1. - r0) * pow(1. - cos, 5);
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

inline __device__ void scatterGlass(PerRayData& prd, const TrianglesGeomData& self) {
    using namespace owl;

    const vec3f rayDir = normalize(static_cast<vec3f>(optixGetWorldRayDirection()));
    const vec3f rayOrg = optixGetWorldRayOrigin();
    const auto tmax = optixGetRayTmax();
    const auto material = *self.material;
    vec3f normal = getPrimitiveNormal(self);

    vec3f outward_normal;
    vec3f reflected = reflect(rayDir, normal);
    float ni_over_nt;
    prd.colour = vec3f(1.f, 1.f, 1.f);
    vec3f refracted;
    float reflect_prob;
    float cosine;

    if (dot(rayDir, normal) > 0.f) {
        outward_normal = -normal;
        ni_over_nt = material.refraction_idx;
        cosine = dot(rayDir, normal);
        cosine = sqrtf(1.f - material.refraction_idx*material.refraction_idx*(1.f-cosine*cosine));
    }
    else {
        outward_normal = normal;
        ni_over_nt = 1.0 / material.refraction_idx;
        cosine = -dot(rayDir, normal);// / vec3f(dir).length();
    }
    if (refract(rayDir, outward_normal, ni_over_nt, refracted))
        reflect_prob = schlickReflectance(cosine, material.refraction_idx);
    else
        reflect_prob = 1.f;

    prd.scattered.s_origin = rayOrg + tmax * rayDir;
    if (prd.random() < reflect_prob) {
        prd.scattered.s_direction = reflected;
    } else {
        prd.scattered.s_direction = refracted;
    }

    prd.scattered.normal_at_hitpoint = normal;
    prd.event = Scattered;
}