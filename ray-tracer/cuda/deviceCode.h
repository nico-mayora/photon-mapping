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

#pragma once

#include <owl/owl.h>
#include <owl/common/math/vec.h>
#include <owl/common/math/random.h>
#include "../shared/common.h"

typedef owl::LCG<4> Random;

/* variables for the triangle mesh geometry */
struct TrianglesGeomData
{
    /*! material we use for the entire mesh */
    Material *material;
    /*! array/buffer of vertex indices */
    owl::vec3i *index;
    /*! array/buffer of vertex positions */
    owl::vec3f *vertex;
};

/* variables for the ray generation program */
struct RayGenData
{
    uint32_t *fbPtr;
    owl::vec2i  fbSize;
    OptixTraversableHandle world;

    struct {
        owl::vec3f origin;
        owl::vec3f lower_left_corner;
        owl::vec3f horizontal;
        owl::vec3f vertical;
    } camera;
};

enum ScatterEvent {
    Reflected,
    Absorbed,
    Missed,
};

struct PerRayData
{
    Random random;
    struct {
        ScatterEvent scatterEvent;
        owl::vec3f scattered_origin;
        owl::vec3f scattered_direction;
        owl::vec3f attenuation;
    } out;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_color;
};

