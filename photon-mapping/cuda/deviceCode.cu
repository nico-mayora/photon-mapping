#include "../include/deviceCode.h"
#include "../../common/cuda/helpers.h"

#include <optix_device.h>

using namespace owl;

//OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
//{
//  const RayGenData &self = owl::getProgramData<RayGenData>();
//  const vec2i pixelID = owl::getLaunchIndex();
//
//  PerRayData prd;
//  prd.random.init(pixelID.x,pixelID.y);
//
//  LightSource lightSource;
//  auto lightSources = self.lightSources;
//  int photon_id = pixelID.x;
//  for (int i = 0; i < self.lightsNum; i++) {
//    lightSource = lightSources[i];
//    if (photon_id < lightSource.num_photons) {
//      break;
//    } else {
//      photon_id -= lightSource.num_photons;
//    }
//  }
//
//  Ray ray;
//  ray.origin = lightSource.pos;
//  ray.direction = normalize(randomPointInUnitSphere(prd.random));
//  prd.colour = lightSource.rgb;
//
//  bool is_alive = true;
//  owl::vec3f color = lightSource.rgb;
//  for (int i = 0; i < MAX_RAY_BOUNCES; i++) {
//    if (pixelID.x == 0) {
//      //printf("i: %d\n", i);
//      //printf("ray.origin: %f %f %f\n", ray.origin.x, ray.origin.y, ray.origin.z);
//      //printf("is_alive: %d\n", is_alive);
//    }
//    int photon_index = atomicAdd(self.photonsCount, 1);
//    Photon photon;
//    photon.is_alive = false;
//
//    if (is_alive) {
//      owl::traceRay(self.world, ray, prd);
//
//      if (prd.event == Missed || prd.event == Absorbed) {
//        is_alive = false;
//        if (pixelID.x == 0) {
//          //printf("prd event: Missed or Absorbed\n");
//        }
//      }
//
//      if (prd.event == ReflectedDiffuse || prd.event == ReflectedSpecular) {
//
//        if (prd.event == ReflectedDiffuse) {
//          color = prd.colour;
//          photon.color = color;
//          photon.pos = prd.scattered.s_origin;
//          photon.dir = ray.direction;
//          photon.is_alive = true;
//          if (pixelID.x == 0) {
//            //printf("prd event: ReflectedDiffuse, coef: %f\n", prd.material.diffuseCoefficient);
//          }
//        } else {
//          if (pixelID.x == 0) {
//            //printf("prd event: ReflectedSpecular, coef: %f\n", prd.material.reflectivity);
//          }
//        }
//
//        float russian_roulette = prd.random();
//
//        double d = prd.material.diffuseCoefficient;
//        double s = prd.material.reflectivity;
//
//        // Currently objects are either diffuse or specular, and the consequent ray is always stored in prd.scatered
//        // When we support multiple coefs per material, we should check for different rays here
//        if (pixelID.x == 0) {
//          //printf("russian_roulette: %f\n", russian_roulette);
//        }
//        if (russian_roulette < d) {
//          if (pixelID.x == 0) {
//            //printf("russian_roulette < d\n");
//          }
//          ray.origin = prd.scattered.s_origin;
//          ray.direction = prd.scattered.s_direction;
//        } else if (russian_roulette < d + s) {
//          if (pixelID.x == 0) {
//            //printf("russian_roulette < d + s\n");
//          }
//          ray.origin = prd.scattered.s_origin;
//          ray.direction = prd.scattered.s_direction;
//        } else {
//          if (pixelID.x == 0) {
//            //printf("russian_roulette MISS\n");
//          }
//          is_alive = false;
//        }
//      }
//
//      if (prd.event == Refraction) {
//        if (pixelID.x == 0) {
//          //printf("prd event: Refraction\n");
//        }
//        color = prd.colour;
//        ray.origin = prd.scattered.s_origin;
//        ray.direction = prd.scattered.s_direction;
//      }
//    }
//
//    photon.color = vec3f(0.5f, 1.f, 0.2f);
//
//    self.photons[photon_index] = photon;
//  }
//}
//
//OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
//{
//  auto &prd = owl::getPRD<PerRayData>();
//
//  const TrianglesGeomData &self = owl::getProgramData<TrianglesGeomData>();
//  const auto &material = *self.material;
//
//  switch (material.surface_type) {
//    case LAMBERTIAN: {
//      scatterLambertian(prd, self);
//      break;
//    }
//    case SPECULAR: {
//      scatterSpecular(prd, self);
//      break;
//    }
//    case GLASS: {
//      scatterGlass(prd, self);
//      break;
//    }
//    default: {
//      scatterLambertian(prd, self);
//      break;
//    }
//  }
//}
//
//OPTIX_MISS_PROGRAM(miss)()
//{
//  auto &prd = owl::getPRD<PerRayData>();
//  prd.event = Missed;
//}

OPTIX_RAYGEN_PROGRAM(pointLightRayGen)(){
  const auto &self = owl::getProgramData<PointLightRGD>();
  const vec2i id = owl::getLaunchIndex();

  const double u = (double)id.x / self.dims.x;
  const double v = (double)id.y / self.dims.y;
  const double theta = 2.0 * M_PI * u;
  const double phi = acos(2.0 * v - 1.0);

  PhotonMapperPRD prd;
  prd.random.init(id.x, id.y);
  prd.color = self.color;

  Ray ray;
  ray.origin = self.position;
  ray.direction = randomPointInUnitSphere(prd.random);

  for(int i = 0; i < 100; i++) {
    owl::traceRay(self.world, ray, prd);

    if (prd.event & (ABSORBED | SCATTER_DIFFUSE)) {
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

OPTIX_CLOSEST_HIT_PROGRAM(triangleMeshClosestHit)(){
  auto &prd = owl::getPRD<PhotonMapperPRD>();
  const auto &self = owl::getProgramData<TrianglesGeomData>();

  const float specularProb = self.material->specular;

  const vec3f albedo = self.material->albedo;
  const float diffuseProb = max(albedo.x, max(albedo.y, albedo.z)) * (1.0f - specularProb);

  const float randomProb = prd.random();
  if (randomProb < diffuseProb) {
    scatterDiffuse(prd, self);
  } else if (randomProb < diffuseProb + specularProb) {
    scatterSpecular(prd, self);
  } else {
    prd.event = ABSORBED;
  }
}

OPTIX_MISS_PROGRAM(miss)(){
  auto &prd = owl::getPRD<PhotonMapperPRD>();
  prd.event = MISS;
}