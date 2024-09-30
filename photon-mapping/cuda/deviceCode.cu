#include "../include/deviceCode.h"
#include "../../common/cuda/helpers.h"

#include <optix_device.h>

using namespace owl;

OPTIX_RAYGEN_PROGRAM(pointLightRayGen)(){
  const auto &self = owl::getProgramData<PointLightRGD>();
  const vec2i id = owl::getLaunchIndex();

  PhotonMapperPRD prd;
  prd.random.init(id.x, id.y);
  prd.color = self.color;

  Ray ray;
  ray.origin = self.position;
  ray.direction = randomPointInUnitSphere(prd.random);
  ray.tmin = EPS;

  for(int i = 0; i < self.maxDepth; i++) {
    owl::traceRay(self.world, ray, prd);

    if (i > 0 && prd.event & (ABSORBED | SCATTER_DIFFUSE)) {
      int photonIndex = atomicAdd(self.photonsCount, 1);
      auto photon = &self.photons[photonIndex];
      photon->color = prd.color;
      photon->pos = prd.scattered.origin;
    }

    if (prd.event & (SCATTER_DIFFUSE | SCATTER_SPECULAR | SCATTER_REFRACT)) {
      ray.origin = prd.scattered.origin;
      ray.direction = prd.scattered.direction;
      prd.color = prd.scattered.color;
    } else {
      break;
    }
  }
}

inline __device__ void scatterDiffuse(PhotonMapperPRD &prd, const TrianglesGeomData &self) {
  const vec3f rayDir = optixGetWorldRayDirection();
  const vec3f rayOrg = optixGetWorldRayOrigin();
  const vec3f hitPoint = rayOrg + optixGetRayTmax() * rayDir;

  const vec3f normal = getPrimitiveNormal(self);

  prd.event = SCATTER_DIFFUSE;
  prd.scattered.origin = hitPoint;
  prd.scattered.direction = reflectDiffuse(normal, prd.random);
  prd.scattered.color = multiplyColor(self.material->albedo, prd.color);
}

inline __device__ void scatterSpecular(PhotonMapperPRD &prd, const TrianglesGeomData &self) {
  const vec3f rayDir = optixGetWorldRayDirection();
  const vec3f rayOrg = optixGetWorldRayOrigin();
  const vec3f hitPoint = rayOrg + optixGetRayTmax() * rayDir;

  const vec3f normal = getPrimitiveNormal(self);

  prd.event = SCATTER_SPECULAR;
  prd.scattered.origin = hitPoint;
  prd.scattered.direction = reflect(rayDir, normal);
  prd.scattered.color = multiplyColor(self.material->albedo, prd.color);
}

inline __device__ void scatterRefract(PhotonMapperPRD &prd, const TrianglesGeomData &self) {
  const vec3f rayDir = optixGetWorldRayDirection();
  const vec3f rayOrg = optixGetWorldRayOrigin();
  const vec3f hitPoint = rayOrg + optixGetRayTmax() * rayDir;

  const vec3f normal = getPrimitiveNormal(self);

  prd.event = SCATTER_REFRACT;
  prd.scattered.origin = hitPoint;
  prd.scattered.direction = refract(rayDir, normal, self.material->refraction_idx);
  prd.scattered.color = multiplyColor(self.material->albedo, prd.color);
}

OPTIX_CLOSEST_HIT_PROGRAM(triangleMeshClosestHit)(){
  auto &prd = owl::getPRD<PhotonMapperPRD>();
  const auto &self = owl::getProgramData<TrianglesGeomData>();

  const float diffuseProb = self.material->diffuse;
  const float specularProb = self.material->specular + diffuseProb;
  const float transmissionProb = self.material->transmission + specularProb;

  const float randomProb = prd.random();
  if (randomProb < diffuseProb) {
    scatterDiffuse(prd, self);
  } else if (randomProb < diffuseProb + specularProb) {
    scatterSpecular(prd, self);
  } else if (randomProb < transmissionProb) {
    scatterRefract(prd, self);
  } else {
    prd.event = ABSORBED;
  }
}

OPTIX_MISS_PROGRAM(miss)(){
  auto &prd = owl::getPRD<PhotonMapperPRD>();
  prd.event = MISS;
}