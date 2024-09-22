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
#include "../../common/src/material.h"
#include "../../common/src/light.h"

struct Photon {
    owl::vec3f pos;
    owl::vec3f dir;
    int power;
    owl::vec3f color;
    bool is_alive;
};

/* variables for the ray generation program */
struct RayGenData
{
    Photon *fbPtr;
    int fbSize;
    OptixTraversableHandle world;
    int lightsNum;
    LightSource *lightSources;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_color;
};

