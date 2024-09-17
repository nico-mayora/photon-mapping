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
#define SAMPLES_PER_PIXEL 500

using namespace owl;

inline __device__
vec3f tracePath(const RayGenData &self, Ray &ray, PerRayData &prd) {
  if (prd.bounces_ramaining == 0) {
    return vec3f(0.f);
  }
  prd.bounces_ramaining -= 1;

  owl::traceRay(self.world, ray, prd);

  if (prd.event == Absorbed) {
    return vec3f(0.f);
  }

  if (prd.event == Scattered) {
    Ray scattered_ray;
    scattered_ray.direction = prd.scattered.s_direction;
    scattered_ray.origin = prd.scattered.s_origin;

    const auto bounced_colour = tracePath(self, scattered_ray, prd);
    return prd.colour * bounced_colour;
  }

  if (prd.event == Missed) {
    return prd.colour;
  }

  return vec3f(0.f);
}

OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
{
  const RayGenData &self = owl::getProgramData<RayGenData>();
  const vec2i pixelID = owl::getLaunchIndex();

  PerRayData prd;
  prd.random.init(pixelID.x,pixelID.y);

  auto final_colour = vec3f(0.f);
  for (int sample = 0; sample < SAMPLES_PER_PIXEL; sample++) {
    const auto random_eps = vec2f(prd.random(), prd.random());
    const vec2f screen = (vec2f(pixelID)+random_eps) / vec2f(self.fbSize);

    Ray ray;
    ray.origin
      = self.camera.pos;
    ray.direction
      = normalize(self.camera.dir_00
                  + screen.u * self.camera.dir_du
                  + screen.v * self.camera.dir_dv);

    prd.bounces_ramaining = MAX_RAY_BOUNCES;
    auto colour = tracePath(self, ray, prd);

    final_colour += colour;
  }

  final_colour = final_colour * (1.f / SAMPLES_PER_PIXEL);

  const int fbOfs = pixelID.x+self.fbSize.x*pixelID.y;

  self.fbPtr[fbOfs]
    = owl::make_rgba(final_colour);
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<PerRayData>();
  const auto self = owl::getProgramData<TrianglesGeomData>();

  // compute normal:
  const int   primID = optixGetPrimitiveIndex();
  const vec3i index  = self.index[primID];
  const vec3f &A     = self.vertex[index.x];
  const vec3f &B     = self.vertex[index.y];
  const vec3f &C     = self.vertex[index.z];
  const vec3f Ng     = normalize(cross(B-A,C-A));

  // scatter ray:
  const auto scatter_direction = Ng + normalize(randomPointInUnitSphere(prd.random));
  prd.scattered.s_direction = scatter_direction;

  auto tmax = optixGetRayTmax();
  const vec3f rayDir = optixGetWorldRayDirection();
  const vec3f rayOrg = optixGetWorldRayOrigin();
  prd.scattered.s_origin = rayOrg + tmax * rayDir;

  const auto &material = *self.material;

  prd.event = Scattered;
  prd.colour = material.albedo;
}

OPTIX_MISS_PROGRAM(miss)()
{
  const MissProgData &self = owl::getProgramData<MissProgData>();

  auto &prd = owl::getPRD<PerRayData>();
  prd.colour = self.sky_color;
  prd.event = Missed;
}

