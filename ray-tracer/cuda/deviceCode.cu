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
#include <optix_device.h>

using namespace owl;

#define SAMPLES_PER_PIXEL 24
#define MAX_RAY_BOUNCES 50

inline __device__
vec3f tracePath(const RayGenData &self, Ray &ray, PerRayData &prd) {
  vec3f attenuation = 1.f;

  for (int depth=0;depth<MAX_RAY_BOUNCES;depth++) {
    traceRay(self.world, ray,prd);

    // ray didn't hit anything
    if (prd.out.scatterEvent == Missed)
        return attenuation * prd.out.attenuation;

    // ray got absorbed
    if (prd.out.scatterEvent == Absorbed)
      return vec3f(0.f);

    // ray bounced
    attenuation *= prd.out.attenuation;
    ray = Ray(prd.out.scattered_origin, prd.out.scattered_direction, 1e-3f, 1e10f);
  }

  return vec3f(0.f);
}

OPTIX_RAYGEN_PROGRAM(simpleRayGen)()
{
  const RayGenData &self = owl::getProgramData<RayGenData>();
  const vec2i pixelID = owl::getLaunchIndex();

  PerRayData prd;
  prd.random.init(pixelID.x,pixelID.y);

  vec3f color = 0.f;
  for (int sampleID = 0; sampleID < SAMPLES_PER_PIXEL; sampleID++) {
    Ray ray;

    const vec2f pixelSample(prd.random(),prd.random());
    const vec2f screen
      = (vec2f(pixelID)+pixelSample)
      / vec2f(self.fbSize);
    const vec3f origin = self.camera.origin;

    const vec3f direction
      = self.camera.lower_left_corner
      + screen.u * self.camera.horizontal
      + screen.v * self.camera.vertical
      - self.camera.origin;

    ray.origin = origin;
    ray.direction = direction;

    color += tracePath(self, ray, prd);
  }

  const int fbOfs = pixelID.x + self.fbSize.x*pixelID.y;

  self.fbPtr[fbOfs]
    = make_rgba(color / (1.f /SAMPLES_PER_PIXEL));
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

  const vec3f rayDir = optixGetWorldRayDirection();
  const auto &material = *self.material;

  prd.out.attenuation = (.2f + .8f*fabs(dot(rayDir,Ng))) * material.albedo;
}

OPTIX_MISS_PROGRAM(miss)()
{
  const MissProgData &self = owl::getProgramData<MissProgData>();

  PerRayData &prd = owl::getPRD<PerRayData>();
  prd.out.scatterEvent = Missed;
  prd.out.attenuation = self.sky_color;
}

