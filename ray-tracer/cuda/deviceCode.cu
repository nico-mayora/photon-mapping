#include "deviceCode.h"
#include "shading.h"

#include "../../common/cuda/helpers.h"

#include <optix_device.h>
#include "owl/RayGen.h"
#include <cukd/knn.h>

using namespace owl;

inline __device__
vec3f tracePath(const RayGenData &self, Ray &ray, PerRayData &prd) {
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
        * (static_cast<float>(current_light.power));
    }
    prd.colour *= light_colour;

    ray = prd.scattered.ray;

    if (isZero(ray.direction) && isZero(ray.origin)) {
      //printf("current_colour = %f %f %f", prd.colour.x, prd.colour.y, prd.colour.z);
      return prd.colour;
    }
  }
  //printf("current_colourxd = %f %f %f", prd.colour.x, prd.colour.y, prd.colour.z);

  return prd.colour;
}

OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
{
  const RayGenData &self = owl::getProgramData<RayGenData>();
  const vec2i pixelID = owl::getLaunchIndex();

  PerRayData prd;
  prd.random.init(pixelID.x,pixelID.y);
  prd.colour= 1.f;

  // Closest hit doesn't have access to RayGenData, so we need to set this here.
  prd.photons.num = self.numPhotons;
  prd.photons.data = self.photons;

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

  const int x = pixelID.x;
  const int y = self.fbSize.y - pixelID.y;

  const int fbOfs = x+self.fbSize.x*y;

  self.fbPtr[fbOfs]
    = make_rgba(final_colour);
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<PerRayData>();
  const auto self = owl::getProgramData<TrianglesGeomData>();
  const auto material = *self.material;

  auto colour_acum = vec3f(0.f);
  if (material.diffuse > 0.f) {
    diffuseAndCausticReflectence(self, prd);
    colour_acum += prd.colour;
  }

  // As we can only have one scattered ray, we randomly
  // select either transmission or reflection based on
  // the material's indices.
  auto r = prd.random();
  if (r < material.specular) {
    specularReflectence(self, prd);
    colour_acum += prd.colour;
  } else if (r < material.specular + material.transmission) {
    transmissionReflectence(self, prd);
    colour_acum += prd.colour;
  }

  prd.colour = colour_acum;
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
    vec3f &lightVisbility = getPRD<vec3f>();
    lightVisbility = vec3f(1.f);
}

OPTIX_CLOSEST_HIT_PROGRAM(shadow)() { /* unused */}
OPTIX_ANY_HIT_PROGRAM(shadow)() { /* unused */}
