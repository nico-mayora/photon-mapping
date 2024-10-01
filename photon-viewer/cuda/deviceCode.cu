#include "../include/deviceCode.h"
#include "../../common/cuda/helpers.h"
#include <optix_device.h>
#include "owl/RayGen.h"

using namespace owl;

#define EPS 1e-4f

OPTIX_RAYGEN_PROGRAM(photonViewerRayGen)()
{
  const auto &self = owl::getProgramData<PhotonViewerRGD>();
  const int photonId = owl::getLaunchIndex().x;
  const Photon photon = self.photons[photonId];

  if(photon.pixel.x < 0 || photon.pixel.x >= self.frameBufferSize.x ||
     photon.pixel.y < 0 || photon.pixel.y >= self.frameBufferSize.y)
  {
    printf("x: %d, y: %d\n", photon.pixel.x, photon.pixel.y);
    return;
  }

  const auto direction = photon.pos - self.cameraPos;

  Ray ray;
  ray.origin = self.cameraPos;
  ray.direction = normalize(direction);
  ray.tmax = norm3d(direction.x, direction.y, direction.z) - EPS;

  PhotonViewerPRD prd;
  owl::traceRay(self.world, ray, prd);

  if (prd.hit){
    return;
  }

  self.frameBuffer[photon.pixel.x + self.frameBufferSize.x * photon.pixel.y] = make_rgba(photon.color);
}

OPTIX_CLOSEST_HIT_PROGRAM(photonViewerClosestHit)() {
  auto &prd = owl::getPRD<PhotonViewerPRD>();
  prd.hit = true;
}

OPTIX_MISS_PROGRAM(photonViewerMiss)()
{
  auto &prd = owl::getPRD<PhotonViewerPRD>();
  prd.hit = false;
}
