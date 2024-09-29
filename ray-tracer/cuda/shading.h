#pragma once

#include <cukd/knn.h>
#include "../../common/cuda/helpers.h"
#define K_NEAREST_NEIGHBOURS 10
#define K_MAX_DISTANCE 2

// Add these to config file. We have these here for now to iterate better
#define CONE_FILTER_C 5

// We should store the power inside each photon. This is temporary (I hope!)
#define PHOTON_POWER float(0.2)

inline __device__
cukd::HeapCandidateList<K_NEAREST_NEIGHBOURS> KNearestPhotons(float3 queryPoint, Photon* photons, int numPoints, float& sqrDistOfFurthestOneInClosest) {
    cukd::HeapCandidateList<K_NEAREST_NEIGHBOURS> closest(K_MAX_DISTANCE);
    sqrDistOfFurthestOneInClosest = cukd::stackBased::knn<
      cukd::HeapCandidateList<K_NEAREST_NEIGHBOURS>,Photon, Photon_traits
    >(
      closest,queryPoint,photons,numPoints
    );
    return closest;
}


// WIP
inline __device__ void diffuseAndCausticReflectence(const TrianglesGeomData& self, PerRayData& prd) {
    using namespace owl;
    const vec3f rayDir = optixGetWorldRayDirection();
    const vec3f rayOrg = optixGetWorldRayOrigin();
    const auto tmax = optixGetRayTmax();
    const auto material = *self.material;

    auto normal = getPrimitiveNormal(self);
    if (dot(rayDir, normal) > 0.f)
        normal = -normal;

    const auto hit_vec3f = rayOrg + tmax * rayDir;
    float3 hit_point = make_float3(hit_vec3f.x, hit_vec3f.y, hit_vec3f.z);

    //const RayGenData rgd = getProgramData<RayGenData>();
    Photon* photons = prd.photons.data;
    const int num_photons = prd.photons.num;

    float sqrDistOfFurthestOneInClosest = 0.f;
    auto k_closest_photons = KNearestPhotons(hit_point, photons, num_photons, sqrDistOfFurthestOneInClosest);

    // Disk sampling rejection should go here.
    // |<photon - hitpoint, normal>| < EPS => accept. Else reject.

    auto incoming_flux = vec3f(0.f);
    for (int p = 0; p < K_NEAREST_NEIGHBOURS; p++) {
        auto photonID = k_closest_photons.get_pointID(p);
        auto photon = photons[photonID];

        if (isZero(photon.pos)) continue;

        // photons with position zero, are invalid

        // TODO: CONE FILTER
        // auto photon_distance = sqrtf(k_closest_photons.get_dist2(photonID));
        // auto photon_weight = 1 - (photon_distance / (CONE_FILTER_C * distance_to_furthest));

        incoming_flux += (material.diffuse / PI) * vec3f(photon.color) * PHOTON_POWER;
    }

    auto radiance_estimate = incoming_flux / (2*PI*sqrDistOfFurthestOneInClosest);

    prd.colour *= radiance_estimate * material.albedo;
    prd.hit_point = rayOrg + tmax * rayDir;
}

inline __device__ void specularReflectence(const TrianglesGeomData& self, PerRayData& prd) {
    using namespace owl;
    const vec3f rayDir = optixGetWorldRayDirection();
    const vec3f rayOrg = optixGetWorldRayOrigin();
    const auto tmax = optixGetRayTmax();
    const auto normal = getPrimitiveNormal(self);

    const auto reflected = reflect(normalize(rayDir), normal);
    prd.hit_point = rayOrg + tmax * rayDir;
    prd.scattered.ray = Ray(prd.hit_point, normalize(reflected), EPS, INFTY);

    const auto material = *self.material;
    prd.colour *= material.specular * material.albedo;
}

inline __device__ void transmissionReflectence(const TrianglesGeomData &self, PerRayData& prd) {
    using namespace owl;

    const vec3f rayDir = normalize(static_cast<vec3f>(optixGetWorldRayDirection()));
    const vec3f rayOrg = optixGetWorldRayOrigin();
    const auto tmax = optixGetRayTmax();
    const auto material = *self.material;
    vec3f normal = getPrimitiveNormal(self);

    vec3f outward_normal, refracted;
    float ni_over_nt, reflection_coefficient, cosine;

    if (dot(rayDir, normal) > 0.f) {
        outward_normal = -normal;
        ni_over_nt = material.refraction_idx;
        cosine = dot(rayDir, normal);
        cosine = sqrtf(1.f - material.refraction_idx*material.refraction_idx*(1.f-cosine*cosine));
    } else {
        outward_normal = normal;
        ni_over_nt = 1.f / material.refraction_idx;
        cosine = -dot(rayDir, normal);
    }

    if (refract(rayDir, outward_normal, ni_over_nt, refracted))
        reflection_coefficient = schlickFresnelAprox(cosine, material.refraction_idx);
    else
        reflection_coefficient = 1.f;


    vec3f scattered_dir;
    float attenuation = material.transmission;
    if (prd.random() < reflection_coefficient) {
        scattered_dir = reflect(rayDir, normal);
        attenuation = reflection_coefficient;
    } else {
        scattered_dir = refracted;
    }

    prd.colour *= material.albedo * attenuation;
    prd.scattered.normal_at_hitpoint = normal;
    prd.hit_point = rayOrg + tmax * rayDir;
    prd.scattered.ray = Ray(prd.hit_point, scattered_dir, EPS, INFTY);
}