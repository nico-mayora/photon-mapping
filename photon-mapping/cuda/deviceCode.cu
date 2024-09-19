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
#include "helpers.h"

#include <optix_device.h>

#define MAX_RAY_BOUNCES 100
#define EPS 0.1

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

