#pragma once

#include <cukd/knn.h>
#include "../../common/cuda/helpers.h"
#include "deviceCode.h"

#define K_NEAREST_NEIGHBOURS 100
#define K_MAX_DISTANCE 100
#define CONE_FILTER_C 1.1f

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

// inline __device__ owl::vec3f directIllumination(const TrianglesGeomData& self, PerRayData& prd) {
//     using namespace owl;
//     const vec3f rayDir = optixGetWorldRayDirection();
//     const vec3f rayOrg = optixGetWorldRayOrigin();
//     const auto tmax = optixGetRayTmax();
//     const auto material = *self.material;
//
//     auto normal = getPrimitiveNormal(self);
//     if (dot(rayDir, normal) > 0.f)
//         normal = -normal;
//
//     const auto lights = self.lighting.lights;
//     const auto numLights = self.lighting.numLights;
//
//     auto light_colour = vec3f(0.f);
//     for (int l = 0; l < numLights; l++) {
//         auto current_light = lights[l];
//         auto shadow_ray_origin = prd.hit_point;
//         auto light_direction = current_light.pos - shadow_ray_origin;
//         auto distance_to_light = length(light_direction);
//
//         auto light_dot_norm = dot(light_direction, normal);
//         if (light_dot_norm <= 0.f) continue; // light hits "behind" triangle
//
//         vec3f lightVisibility = 0.f;
//         uint32_t u0, u1;
//         packPointer(&lightVisibility, u0, u1);
//         optixTrace(
//           self.world,
//           shadow_ray_origin,
//           normalize(light_direction),
//           EPS,
//           distance_to_light * (1.f - EPS),
//           0.f,
//           OptixVisibilityMask(255),
//           OPTIX_RAY_FLAG_DISABLE_ANYHIT
//           | OPTIX_RAY_FLAG_TERMINATE_ON_FIRST_HIT
//           | OPTIX_RAY_FLAG_DISABLE_CLOSESTHIT,
//           1,
//           2,
//           1,
//           u0, u1
//         );
//
//         light_colour
//           += lightVisibility
//           * current_light.rgb
//           * (light_dot_norm / (distance_to_light * distance_to_light))
//           * (static_cast<float>(current_light.power))
//           * prd.material.albedo;
//     }
//
// }
//
// // WIP - TODO: Separate
// inline __device__ owl::vec3f diffuseAndCausticReflectence(const TrianglesGeomData& self, PerRayData& prd) {
//     using namespace owl;
//     const vec3f rayDir = optixGetWorldRayDirection();
//     const vec3f rayOrg = optixGetWorldRayOrigin();
//     const auto tmax = optixGetRayTmax();
//     const auto material = *self.material;
//
//     auto normal = getPrimitiveNormal(self);
//     if (dot(rayDir, normal) > 0.f)
//         normal = -normal;
//
//     const auto hit_vec3f = rayOrg + tmax * rayDir;
//     float3 hit_point = make_float3(hit_vec3f.x, hit_vec3f.y, hit_vec3f.z);
//
//     //const RayGenData rgd = getProgramData<RayGenData>();
//     Photon* photons = prd.photons.data;
//     const int num_photons = prd.photons.num;
//
//     float sqrDistOfFurthestOneInClosest = 0.f;
//     auto k_closest_photons = KNearestPhotons(hit_point, photons, num_photons, sqrDistOfFurthestOneInClosest);
//
//     // Disk sampling rejection should go here.
//     // |<photon - hitpoint, normal>| < EPS => accept. Else reject.
//
//     auto incoming_flux = vec3f(0.f);
//     for (int p = 0; p < K_NEAREST_NEIGHBOURS; p++) {
//         auto photonID = k_closest_photons.get_pointID(p);
//         auto photon = photons[photonID];
//
//         if (isZero(photon.pos)) continue;
//
//         // photons with position zero, are invalid
//
//         // TODO: CONE FILTER
//         // auto photon_distance = sqrtf(k_closest_photons.get_dist2(photonID));
//         // auto photon_weight = 1 - (photon_distance / (CONE_FILTER_C * distance_to_furthest));
//
//         incoming_flux += (material.diffuse / PI) * vec3f(photon.color) * PHOTON_POWER;
//     }
//
//     auto radiance_estimate = incoming_flux / (2*PI*sqrDistOfFurthestOneInClosest);
//
//     prd.colour *= radiance_estimate * material.albedo;
//     prd.hit_point = rayOrg + tmax * rayDir;
// }
//

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
     for (int p = 0; p < K_NEAREST_NEIGHBOURS; p++) {
         const auto photonID = k_nearest.get_pointID(p);
         auto photon = photons[photonID];

         if (isZero(photon.pos)) continue;

         const auto photon_power = photon.power;
         const auto photon_distance = norm(vec3f(photon.pos) - hitpoint);
         const auto photon_weight = 1 - (photon_distance / sqrtf(query_area_radius_squared) * CONE_FILTER_C);

         in_flux += diffuse_brdf
           * photon_power * photon_weight
           * vec3f(photon.color);
     }

     return in_flux / ((1 - (2/3) * (1.f/CONE_FILTER_C)) * 2*PI*query_area_radius_squared);
 }

