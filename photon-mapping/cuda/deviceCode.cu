#include "deviceCode.h"
#include "../../common/cuda/helpers.h"
#define PHOTON_ATTENUATION_FACTOR 150
#define ATTENUATE_PHOTONS false

#include <optix_device.h>

using namespace owl;

inline __device__
vec3f calculateTransmissionDirection(const vec3f &normal, const vec3f &direction, const float refraction_idx, float random) {
  const auto reflected = reflect(normalize(direction), normal);
  vec3f outward_normal;
  vec3f refracted;
  float reflect_prob;
  float cosine;
  float ni_over_nt;

  if (dot(direction, normal) > 0.f) {
    outward_normal = -normal;
    ni_over_nt = refraction_idx;
    cosine = dot(direction, normal);
    cosine = sqrtf(1.f - refraction_idx*refraction_idx*(1.f-cosine*cosine));
  } else {
    outward_normal = normal;
    ni_over_nt = 1.0 / refraction_idx;
    cosine = -dot(direction, normal);// / vec3f(dir).length();
  }

  if (refract(direction, outward_normal, ni_over_nt, refracted))
    reflect_prob = schlickFresnelAprox(cosine, refraction_idx);
  else
    reflect_prob = 1.f;

  if (random < reflect_prob) {
    return reflected;
  } else {
    return refracted;
  }
}

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
  prd.colour = lightSource.rgb;

  bool is_alive = true;
  owl::vec3f color = lightSource.rgb;
  for (int i = 0; i < MAX_RAY_BOUNCES; i++) {
//    if (pixelID.x == 0) {
//      printf("i: %d\n", i);
//      printf("ray.origin: %f %f %f\n", ray.origin.x, ray.origin.y, ray.origin.z);
//      printf("is_alive: %d\n", is_alive);
//    }
    int photon_index = (pixelID.x *  MAX_RAY_BOUNCES) + i;
    Photon photon;
    photon.is_alive = false;

    if (is_alive) {
      owl::traceRay(self.world, ray, prd);

      float russian_roulette = prd.random();

      double d = prd.material.diffuse;
      double s = prd.material.specular;
      double t = prd.material.transmission;

//      if (pixelID.x == 0) {
//        printf("russian_roulette: %f\n", russian_roulette);
//      }
      if (ATTENUATE_PHOTONS && prd.hit_point.distance) {
        color = clampvec(color * PHOTON_ATTENUATION_FACTOR / (prd.hit_point.distance * prd.hit_point.distance), 1);
      }

      if (russian_roulette < d) {
        // Diffuse
        photon.color = color;
        photon.pos = prd.hit_point.origin;
        photon.dir = prd.hit_point.direction;
        photon.is_alive = true;

        auto scatter_direction = prd.hit_point.normal + normalize(randomPointInUnitSphere(prd.random));
        if (dot(scatter_direction, scatter_direction) < EPS) {
          scatter_direction = prd.hit_point.normal;
        }
        ray.origin = prd.hit_point.origin;
        ray.direction = normalize(scatter_direction);
        color *= prd.material.albedo;
      } else if (russian_roulette < d + s) {
        // Specular
        const auto reflected = reflect(normalize(prd.hit_point.direction), prd.hit_point.normal);
        ray.origin = prd.hit_point.origin;
        ray.direction = reflected;
        color *= prd.material.albedo;
      } else if (russian_roulette < d + s + t) {
        // Transmission
        ray.origin = prd.hit_point.origin;
        ray.direction = calculateTransmissionDirection(prd.hit_point.normal, prd.hit_point.direction, prd.material.refraction_idx, prd.random());
        color *= prd.material.albedo;
      } else {
        is_alive = false;
      }
    }
    self.photons[photon_index] = photon;
  }
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<PerRayData>();

  const TrianglesGeomData &self = owl::getProgramData<TrianglesGeomData>();
  const auto &material = *self.material;

  const vec3f rayDir = optixGetWorldRayDirection();
  const vec3f rayOrg = optixGetWorldRayOrigin();
  const vec3f Ng = getPrimitiveNormal(self);
  const float t = optixGetRayTmax();

  // Copy material to prd
  prd.material.albedo = material.albedo;
  prd.material.diffuse = material.diffuse;
  prd.material.specular = material.specular;
  prd.material.transmission = material.transmission;
  prd.material.refraction_idx = material.refraction_idx;

  // Populate ray data
  prd.hit_point.origin = rayOrg + t * rayDir;
  prd.hit_point.direction = rayDir;
  prd.hit_point.normal = Ng;
  prd.hit_point.distance = norm(t * rayDir);
}

OPTIX_MISS_PROGRAM(miss)()
{
  auto &prd = owl::getPRD<PerRayData>();
  prd.material.diffuse = 0;
  prd.material.specular = 0;
  prd.material.transmission = 0;
}

