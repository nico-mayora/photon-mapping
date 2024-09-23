#include "deviceCode.h"
#include "../../common/cuda/helpers.h"

#include <optix_device.h>

#define MAX_RAY_BOUNCES 100

using namespace owl;

OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
{
  const RayGenData &self = owl::getProgramData<RayGenData>();
  const vec2i pixelID = owl::getLaunchIndex();

  PerRayData prd;
  prd.random.init(pixelID.x,pixelID.y);

  LightSource lightSource;
  auto lightSources = self.lightSources;
  int photon_id = pixelID.x;
  for (int i = 0; i < self.lightsNum; i++) {
    lightSource = lightSources[i];
    if (photon_id < lightSource.num_photons) {
      break;
    } else {
      photon_id -= lightSource.num_photons;
    }
  }

  Ray ray;
  ray.origin = lightSource.pos;
  ray.direction = normalize(randomPointInUnitSphere(prd.random));

  Photon out_photon;
  out_photon.is_alive = true;
  owl::traceRay(self.world, ray, out_photon);

  const int fbOfs = pixelID.x;
  self.fbPtr[fbOfs] = out_photon;
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<Photon>();

  const TrianglesGeomData &self = owl::getProgramData<TrianglesGeomData>();
  const vec3f rayDir = optixGetWorldRayDirection();
  const vec3f rayOrg = optixGetWorldRayOrigin();
  const auto tmax = optixGetRayTmax();
  const auto &material = *self.material;

  prd.pos = rayOrg + (tmax * rayDir);

  prd.dir = normalize(rayDir);
  prd.color = material.albedo;
  prd.power = 1.f;
}

OPTIX_MISS_PROGRAM(miss)()
{
  auto &prd = owl::getPRD<Photon>();
  prd.is_alive = false;
}

