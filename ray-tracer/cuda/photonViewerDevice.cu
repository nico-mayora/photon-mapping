#include "../include/deviceCode.h"
#include "../../common/cuda/helpers.h"

#include <optix_device.h>
#include "owl/RayGen.h"
#include "../include/photonViewer.h"
#include <cukd/knn.h>

#define PHOTON_RADIUS 1

using namespace owl;

OPTIX_RAYGEN_PROGRAM(photonViewerRayGen)()
{
  const auto &self = owl::getProgramData<PhotonViewerRGD>();
  const vec2i pixel = owl::getLaunchIndex();
  const vec2f screenSpacePosition = vec2f(pixel) / vec2f(self.frameBufferSize);

  Ray ray;
  ray.origin = self.camera.pos;
  ray.direction = normalize(self.camera.dir_00
                      + screenSpacePosition.u * self.camera.dir_du
                      + screenSpacePosition.v * self.camera.dir_dv);

  PhotonViewerPRD prd;
  owl::traceRay(self.world, ray, prd);

  vec3f color(0.f);
  if (prd.hit){
    cukd::FixedCandidateList<1> closest(PHOTON_RADIUS);
    cukd::stackBased::knn<cukd::FixedCandidateList<1>,Photon, Photon_traits>(closest, prd.hitPoint, self.photons, self.numPhotons);

    if (pixel.x == 200 && pixel.y == 200){
      Photon photon = self.photons[closest.get_pointID(0)];
      printf("Closest point: %d %f %f %f\n", closest.get_pointID(0), photon.color.x, photon.color.y, photon.color.z);
    }

    color = self.photons[closest.get_pointID(0)].color;
  }

  self.frameBuffer[pixel.x + self.frameBufferSize.x * pixel.y] = make_rgba(color);
}

OPTIX_CLOSEST_HIT_PROGRAM(photonViewerClosestHit)()
{
  const vec3f origin = optixGetWorldRayOrigin();
  const vec3f direction = optixGetWorldRayDirection();
  const auto time = optixGetRayTime();

  auto &prd = owl::getPRD<PhotonViewerPRD>();
  prd.hit = true;
  prd.hitPoint = origin + direction * time;
}

OPTIX_MISS_PROGRAM(photonViewerMiss)()
{
  auto &prd = owl::getPRD<PhotonViewerPRD>();
  prd.hit = false;
}
