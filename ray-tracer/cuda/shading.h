#pragma once

#include <cukd/knn.h>
#include "../../common/cuda/helpers.h"
#include "../include/deviceCode.h"

#define K_NEAREST_NEIGHBOURS 50
#define K_MAX_DISTANCE 100
#define CONE_FILTER_C 1.2f

inline __device__
cukd::HeapCandidateList<K_NEAREST_NEIGHBOURS> KNearestPhotons(float3 queryPoint, Photon* photons, int numPoints, float& sqrDistOfFurthestOneInClosest) {
    cukd::HeapCandidateList<K_NEAREST_NEIGHBOURS> closest(K_MAX_DISTANCE);
    sqrDistOfFurthestOneInClosest = cukd::stackBased::knn<
        cukd::HeapCandidateList<K_NEAREST_NEIGHBOURS>,Photon, Photon_traits
    >(closest,queryPoint,photons,numPoints);
 return closest;
}

inline __device__
owl::vec3f calculate_refracted(const Material& material,
                               const owl::vec3f& ray_dir,
                               const owl::vec3f& normal,
                               Random rand)
{
    using namespace owl;

    vec3f outward_normal, refracted;
    float ni_over_nt, reflection_coefficient, cosine;

    if (dot(ray_dir, normal) > 0.f) {
        outward_normal = -normal;
        ni_over_nt = material.refraction_idx;
        cosine = dot(ray_dir, normal);
        cosine = sqrtf(1.f - material.refraction_idx*material.refraction_idx*(1.f-cosine*cosine));
    } else {
        outward_normal = normal;
        ni_over_nt = 1.f / material.refraction_idx;
        cosine = -dot(ray_dir, normal);
    }

    if (refract(ray_dir, outward_normal, ni_over_nt, refracted))
        reflection_coefficient = schlickFresnelAprox(cosine, material.refraction_idx);
    else
        reflection_coefficient = 1.f;

    vec3f scattered_dir;
    if (rand() < reflection_coefficient) {
        scattered_dir = reflect(ray_dir, normal);
    } else {
        scattered_dir = refracted;
    }

    return scattered_dir;
}

inline __device__
owl::vec3f reflect_or_refract_ray(const Material& material,
                                                    const owl::vec3f& ray_dir,
                                                    const owl::vec3f& normal,
                                                    Random rand,
                                                    bool& absorbed,
                                                    float& coef)
{
    absorbed = false;

    auto r = rand();
    if (r < material.specular) {
        coef = material.specular;
        return reflect(ray_dir, normal);
    }
    if (r < material.specular + material.transmission) {
        coef = material.transmission;
        return calculate_refracted(material, ray_dir, normal, rand);
    }

    coef = 0.f;
    absorbed = true;
    return 0.f;
}

inline __device__ float specularBrdf(const float specular_coefficient,
                                      const owl::vec3f& incoming_light_dir,
                                      const owl::vec3f& outgoing_light_dir,
                                      const owl::vec3f& normal) {
    if (const auto reflected_incoming = reflect(incoming_light_dir, normal);
        nearZero(reflected_incoming - outgoing_light_dir))
        return specular_coefficient;

    return 0;
}

inline __device__
owl::vec3f gatherPhotons(const owl::vec3f& hitpoint, Photon* photons, const int num_photons,const float diffuse_brdf) {
     using namespace owl;
     float query_area_radius_squared = 0.f;
     auto k_nearest = KNearestPhotons(
       hitpoint, photons, num_photons, query_area_radius_squared
     );

     auto in_flux = vec3f(0.f);
     #pragma unroll
     for (int p = 0; p < K_NEAREST_NEIGHBOURS; p++) {
         const auto photonID = k_nearest.get_pointID(p);
         if (photonID < 0 || photonID > num_photons) continue;
         auto photon = photons[photonID];

         const auto photon_power = photon.power;
         const auto photon_distance = norm(vec3f(photon.pos) - hitpoint);
         const auto photon_weight = 1 - (photon_distance / sqrtf(query_area_radius_squared) * CONE_FILTER_C);

         in_flux += diffuse_brdf
           * photon_power * photon_weight
           * vec3f(photon.color);
     }

     return in_flux / ((1 - (2.f/3.f) * (1.f/CONE_FILTER_C)) * 2*PI*query_area_radius_squared);
 }

