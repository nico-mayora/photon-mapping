#include "deviceCode.h"
#include "../../common/cuda/helpers.h"

#include <optix_device.h>
#include "owl/RayGen.h"

#define MAX_RAY_BOUNCES 100
#define SAMPLES_PER_PIXEL 1000
#define LIGHT_FACTOR 1.f
#define AMBIENT_LIGHT false

using namespace owl;

inline __device__
vec3f tracePath(const RayGenData &self, Ray &ray, PerRayData &prd) {
  auto acum = vec3f(1.);

  uint32_t p0, p1;
  packPointer( &prd, p0, p1 );
  for (int i = 0; i < MAX_RAY_BOUNCES; i++) {
    optixTrace(self.world,
      ray.origin,
      ray.direction,
      EPS,
      1e10,
      0.f,
      OptixVisibilityMask(255),
      OPTIX_RAY_FLAG_DISABLE_ANYHIT,
      0,
      2,
      0,
      p0, p1
    );

    if (prd.event == Absorbed) {
      return vec3f(0.f);
    }

    if (prd.event == Missed) {
      if (i == 0) {
        return prd.colour; // sky colour
      }
      if (AMBIENT_LIGHT) {
        return acum * prd.colour;
      }
      return acum;
    }

    /* prd.event is not Absorbed or Missed */
    ray = Ray(prd.scattered.s_origin, prd.scattered.s_direction, EPS, 1e10f);
    auto colour_before_shadow = prd.colour;

    /* trace shadow rays */
    vec3f light_colour = vec3f(0.f);

    const auto lights = self.lights;
    const auto numLights = self.numLights;

    for (int l = 0; l < numLights; l++) {
      auto current_light = lights[l];
      auto shadow_ray_origin = prd.scattered.s_origin;
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
        += lightVisibility * LIGHT_FACTOR
        * current_light.rgb
        * (light_dot_norm / (distance_to_light * distance_to_light))
        * (static_cast<float>(current_light.power) / numLights)
        * (1.f / SAMPLES_PER_PIXEL);
    }

    if (AMBIENT_LIGHT) {
      light_colour += LIGHT_FACTOR * self.sky_color * (1.f / SAMPLES_PER_PIXEL);
    }

    acum *= colour_before_shadow * light_colour;
  }

  return acum;
}

OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
{
  const RayGenData &self = owl::getProgramData<RayGenData>();
  const vec2i pixelID = owl::getLaunchIndex();

  PerRayData prd;
  prd.random.init(pixelID.x,pixelID.y);

  auto final_colour = vec3f(0.f);
  for (int sample = 0; sample < SAMPLES_PER_PIXEL; sample++) {
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

  final_colour = final_colour * (1.f / SAMPLES_PER_PIXEL);

  const int fbOfs = pixelID.x+self.fbSize.x*pixelID.y;

  self.fbPtr[fbOfs]
    = make_rgba(final_colour);
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<PerRayData>();
  const auto self = owl::getProgramData<TrianglesGeomData>();
  const auto &material = *self.material;

  switch (material.surface_type) {
    case LAMBERTIAN: {
      scatterLambertian(prd, self);
      break;
    }
    case SPECULAR: {
      scatterSpecular(prd, self);
      break;
    }
    case GLASS: {
      scatterGlass(prd, self);
      break;
    }
    default: {
      scatterLambertian(prd, self);
      break;
    }
  }
}

OPTIX_MISS_PROGRAM(miss)()
{
  const MissProgData &self = owl::getProgramData<MissProgData>();

  auto &prd = owl::getPRD<PerRayData>();
  prd.colour = self.sky_color;
  prd.event = Missed;
}

OPTIX_MISS_PROGRAM(shadow)()
{
    // we didn't hit anything, so the light is visible
    vec3f &prd = getPRD<vec3f>();
    prd = vec3f(1.f);
}

OPTIX_CLOSEST_HIT_PROGRAM(shadow)() { /* unused */}
OPTIX_ANY_HIT_PROGRAM(shadow)() { /* unused */}
