#include "../include/deviceCode.h"
#include "shading.h"

#include "../../common/cuda/helpers.h"

#include <optix_device.h>
#include "owl/RayGen.h"
#include <cukd/knn.h>

using namespace owl;

inline __device__
vec3f tracePath(const RayGenData &self, Ray &ray, PerRayData &prd) {
  auto acum = vec3f(1.);

  uint32_t p0, p1;
  packPointer( &prd, p0, p1 );
  for (int i = 0; i < self.max_ray_depth; i++) {
    prd.scattered.ray = Ray(0.f, 0.f, EPS, INFTY);

    optixTrace(self.world,
      ray.origin,
      ray.direction,
      ray.tmin,
      ray.tmax,
      0.f,
      OptixVisibilityMask(255),
      OPTIX_RAY_FLAG_DISABLE_ANYHIT,
      0,
      2,
      0,
      p0, p1
    );

    /* trace shadow rays */
    vec3f light_colour = vec3f(0.f);

    const auto lights = self.lights;
    const auto numLights = self.numLights;

    for (int l = 0; l < numLights; l++) {
      auto current_light = lights[l];
      auto shadow_ray_origin = prd.hit_point;
      auto light_direction = current_light.pos - shadow_ray_origin;
      auto distance_to_light = length(light_direction);
      const auto normal = prd.scattered.normal_at_hitpoint;

      auto light_dot_norm = dot(light_direction, normal);
      if (light_dot_norm <= 0.f) continue; // light hits "behind" triangle

      vec3f lightVisibility = 0.f;
      uint32_t u0, u1;
      packPointer(&lightVisibility, u0, u1);
      optixTrace(
        self.world,
        shadow_ray_origin,
        normalize(light_direction),
        EPS,
        distance_to_light * (1.f - EPS),
        0.f,
        OptixVisibilityMask(255),
        OPTIX_RAY_FLAG_DISABLE_ANYHIT
        | OPTIX_RAY_FLAG_TERMINATE_ON_FIRST_HIT
        | OPTIX_RAY_FLAG_DISABLE_CLOSESTHIT,
        1,
        2,
        1,
        u0, u1
      );
      light_colour
        += lightVisibility
        * current_light.rgb
        * (light_dot_norm / (distance_to_light * distance_to_light))
        * (static_cast<float>(current_light.power) / numLights)
        * (1.f / self.samples_per_pixel);
    }

    if (isZero(prd.scattered.ray.direction) && isZero(prd.scattered.ray.origin)) {
      return prd.colour;
    }

    ray = prd.scattered.ray;
  }

  return prd.colour;
}

inline __device__
cukd::FixedCandidateList<K_NEAREST_NEIGHBOURS> KNearestPhotons(float3 queryPoint, Photon* photons, int numPoints) {
  cukd::FixedCandidateList<K_NEAREST_NEIGHBOURS> closest(K_MAX_DISTANCE);
  auto sqrDistOfFurthestOneInClosest = cukd::stackBased::knn<
    cukd::FixedCandidateList<K_NEAREST_NEIGHBOURS>,Photon, Photon_traits
  >(
    closest,queryPoint,photons,numPoints
  );
  return closest;
}

OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
{
  const RayGenData &self = owl::getProgramData<RayGenData>();
  const vec2i pixelID = owl::getLaunchIndex();

  if (pixelID.x == 0 && pixelID.y == 0){
    for (int i=0; i<5; i++) {
      printf("photon %d: %f %f %f\n", i, self.photons[i].pos.x, self.photons[i].pos.y, self.photons[i].pos.z);
    }
  }

  PerRayData prd;
  prd.random.init(pixelID.x,pixelID.y);
  prd.attenuation = 1.f;

  if (pixelID.x == 0 && pixelID.y == 0) {
    auto queryPoint = make_float3(0.f, 0.f, 0.f);
    auto closest = KNearestPhotons(queryPoint, self.photons, self.numPhotons);

    for (int i = 0; i < K_NEAREST_NEIGHBOURS; i++) {
      auto id = closest.get_pointID(i);
      auto photon = self.photons[id];
      printf("Closest point %d: %f %f %f, %f %f %f\n", i, photon.pos.x, photon.pos.y, photon.pos.z, photon.color.x, photon.color.y, photon.color.z);
    }
  }


  auto final_colour = vec3f(0.f);
  for (int sample = 0; sample < self.samples_per_pixel; sample++) {
    const auto random_eps = vec2f(prd.random(), prd.random());
    const vec2f screen = (vec2f(pixelID)+random_eps) / vec2f(self.fbSize);

    Ray ray;
    ray.origin
      = self.camera.pos;
    ray.direction
      = normalize(self.camera.dir_00
                  + screen.u * self.camera.dir_du
                  + screen.v * self.camera.dir_dv);

    const auto colour = tracePath(self, ray, prd);

    final_colour += colour;
  }

  final_colour = final_colour * (1.f / self.samples_per_pixel);

  const int fbOfs = pixelID.x+self.fbSize.x*pixelID.y;

  self.fbPtr[fbOfs]
    = make_rgba(final_colour);
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<PerRayData>();
  const auto self = owl::getProgramData<TrianglesGeomData>();
  const auto rgd = owl::getProgramData<RayGenData>();
  const auto material = *self.material;

  if (material.diffuse > 0.f)
    //diffuseAndCausticReflectence(self, prd, rgd);


  // As we can only have one scattered ray, we randomly
  // select either transmission or reflection based on
  // the material's indices.
  if (prd.random() < material.specular / (material.diffuse + material.specular)) {
    specularReflectence(self, prd);
  } else {
    transmissionReflectence(self, prd);
  }
}

OPTIX_MISS_PROGRAM(miss)()
{
  const MissProgData &self = owl::getProgramData<MissProgData>();

  auto &prd = owl::getPRD<PerRayData>();
  prd.colour = self.sky_colour;
}

OPTIX_MISS_PROGRAM(shadow)()
{
    // we didn't hit anything, so the light is visible
    vec3f &prd = getPRD<vec3f>();
    prd = vec3f(1.f);
}

OPTIX_CLOSEST_HIT_PROGRAM(shadow)() { /* unused */}
OPTIX_ANY_HIT_PROGRAM(shadow)() { /* unused */}
