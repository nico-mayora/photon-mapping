// ======================================================================== //
// Copyright 2019-2020 Ingo Wald                                            //
//                                                                          //
// Licensed under the Apache License, Version 2.0 (the "License");          //
// you may not use this file except in compliance with the License.         //
// You may obtain a copy of the License at                                  //
//                                                                          //
//     http://www.apache.org/licenses/LICENSE-2.0                           //
//                                                                          //
// Unless required by applicable law or agreed to in writing, software      //
// distributed under the License is distributed on an "AS IS" BASIS,        //
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. //
// See the License for the specific language governing permissions and      //
// limitations under the License.                                           //
// ======================================================================== //

#include "deviceCode.h"
#include "../../common/cuda/helpers.h"

#include <optix_device.h>

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
  prd.colour = lightSource.rgb;

  bool is_alive = true;
  owl::vec3f color = lightSource.rgb;
  for (int i = 0; i < MAX_RAY_BOUNCES; i++) {
    if (pixelID.x == 0) {
      printf("i: %d\n", i);
      printf("ray.origin: %f %f %f\n", ray.origin.x, ray.origin.y, ray.origin.z);
      printf("is_alive: %d\n", is_alive);
    }
    int photon_index = pixelID.x + i;
    Photon photon;
    photon.is_alive = false;

    if (is_alive) {
      owl::traceRay(self.world, ray, prd);

      if (prd.event == Missed || prd.event == Absorbed) {
        is_alive = false;
        if (pixelID.x == 0) {
          printf("prd event: Missed or Absorbed\n");
        }
      }

      if (prd.event == ReflectedDiffuse || prd.event == ReflectedSpecular) {

        if (prd.event == ReflectedDiffuse) {
          color *= prd.colour;
          photon.color = color;
          photon.pos = prd.scattered.s_origin;
          photon.dir = ray.direction;
          photon.is_alive = true;
          if (pixelID.x == 0) {
            printf("prd event: ReflectedDiffuse, coef: %f\n", prd.material.diffuseCoefficient);
          }
        } else {
          if (pixelID.x == 0) {
            printf("prd event: ReflectedSpecular, coef: %f\n", prd.material.reflectivity);
          }
        }

        float russian_roulette = prd.random();

        double d = prd.material.diffuseCoefficient;
        double s = prd.material.reflectivity;

        // Currently objects are either diffuse or specular, and the consequent ray is always stored in prd.scatered
        // When we support multiple coefs per material, we should check for different rays here
        if (pixelID.x == 0) {
          printf("russian_roulette: %f\n", russian_roulette);
        }
        if (russian_roulette < d) {
          if (pixelID.x == 0) {
            printf("russian_roulette < d\n");
          }
          ray.origin = prd.scattered.s_origin;
          ray.direction = prd.scattered.s_direction;
        } else if (russian_roulette < d + s) {
          if (pixelID.x == 0) {
            printf("russian_roulette < d + s\n");
          }
          ray.origin = prd.scattered.s_origin;
          ray.direction = prd.scattered.s_direction;
        } else {
          if (pixelID.x == 0) {
            printf("russian_roulette MISS\n");
          }
          is_alive = false;
        }
      }

      if (prd.event == Refraction) {
        if (pixelID.x == 0) {
          printf("prd event: Refraction\n");
        }
        color *= prd.colour;
        ray.origin = prd.scattered.s_origin;
        ray.direction = prd.scattered.s_direction;
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
  auto &prd = owl::getPRD<PerRayData>();
  prd.event = Missed;
}

