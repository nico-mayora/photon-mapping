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
  for (int i = 0; i < MAX_RAY_BOUNCES; i++) {
    owl::traceRay(self.world, ray, prd);

    if (prd.event == Missed || prd.event == Absorbed) {
      break;
    }

    if (prd.event == ReflectedDiffuse) {
      //int j = atomicAdd(&self.photonsCount, 1);
      int j = pixelID.x;

      self.photons[j].color = prd.colour;
      self.photons[j].pos = prd.scattered.s_origin;
      self.photons[j].dir = prd.scattered.s_direction;
      self.photons[j].is_alive = true;
    }

    ray.origin = prd.scattered.s_origin;
    ray.direction = prd.scattered.s_direction;
  }
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<PerRayData>();

  const TrianglesGeomData &self = owl::getProgramData<TrianglesGeomData>();
  const vec3f rayDir = optixGetWorldRayDirection();
  const vec3f rayOrg = optixGetWorldRayOrigin();
  const auto tmax = optixGetRayTmax();
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

