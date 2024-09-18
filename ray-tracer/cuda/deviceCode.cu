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

#define MAX_RAY_BOUNCES 30
#define SAMPLES_PER_PIXEL 250


using namespace owl;

inline __device__
vec3f tracePath(const RayGenData &self, Ray &ray, PerRayData &prd) {
  auto acum = vec3f(1.);

  for (int i = 0; i < MAX_RAY_BOUNCES; i++) {
    traceRay(self.world, ray, prd);

    if (prd.event == Absorbed) {
      return vec3f(0.f);
    }

    if (prd.event == Scattered) {
      ray = Ray(prd.scattered.s_origin, prd.scattered.s_direction, EPS, 1e10f);
      acum *= prd.colour;
    }

    if (prd.event == Missed) {
      return acum * prd.colour;
    }
  }

  return acum;
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

    const auto colour = tracePath(self, ray, prd);

    final_colour += colour;
  }

  final_colour = final_colour * (1.f / SAMPLES_PER_PIXEL);

  const int fbOfs = pixelID.x+self.fbSize.x*pixelID.y;

  self.fbPtr[fbOfs]
    = make_rgba(final_colour);
}

OPTIX_CLOSEST_HIT_PROGRAM(TriangleMesh)()
{
  auto &prd = owl::getPRD<PerRayData>();
  const auto self = owl::getProgramData<TrianglesGeomData>();
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
  const MissProgData &self = owl::getProgramData<MissProgData>();

  auto &prd = owl::getPRD<PerRayData>();
  prd.colour = self.sky_color;
  prd.event = Missed;
}

