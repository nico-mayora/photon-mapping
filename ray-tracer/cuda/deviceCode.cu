#include "deviceCode.h"
#include "shading.h"

#include "../../common/cuda/helpers.h"

#include <optix_device.h>
#include "owl/RayGen.h"
#include <cukd/knn.h>
#define LIGHT_COLOR_FACTOR 0.1f

using namespace owl;

inline __device__
vec3f tracePath(const RayGenData &self, Ray &ray, PerRayData &prd) {
  // Accumulates the colour for each "recursive" step
  auto ray_colour = vec3f(1.f);

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

    ray = prd.scattered.ray;

    ray_colour *= prd.colour;

    ray = prd.scattered.ray;
    if (isZero(ray.direction) && isZero(ray.origin)) {
      //printf("current_colour = %f %f %f", prd.colour.x, prd.colour.y, prd.colour.z);
      return ray_colour;
    }

  }
  //printf("current_colourxd = %f %f %f", prd.colour.x, prd.colour.y, prd.colour.z);
  return ray_colour;
}

OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
{
  const RayGenData &self = owl::getProgramData<RayGenData>();
  const vec2i pixelID = owl::getLaunchIndex();

  // if coords debug == true

  PerRayData prd;
  prd.random.init(pixelID.x,pixelID.y);
  prd.colour= 1.f;

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

  auto reflected_radiace = vec3f(0.f);
  if (material.diffuse > 0.f) {
    reflected_radiace += diffuseAndCausticReflectence(self, prd);
  }

  // As we can only have one scattered ray, we randomly
  // select either transmission or reflection based on
  // the material's indices.
  auto r = prd.random();
  if (r < material.specular) {
    reflected_radiace += specularReflectence(self, prd);
  } else if (r < material.specular + material.transmission) {
    transmissionReflectence(self, prd);
    reflected_radiace += prd.colour;
  }

  prd.colour = reflected_radiace;
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
