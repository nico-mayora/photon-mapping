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
#include <cukd/data.h>
#include "../../common/src/material.h"
#include "../../common/src/light.h"

struct Photon {
    // Data for the photon
    float3 pos;
    float3 dir;
    float3 color;
    // Data for KD-tree
    uint8_t quantized_normal[3];
    uint8_t split_dim;
};

struct Photon_traits : public cukd::default_data_traits<float3> {
    using point_t = float3;
    // set to false because "optimized" KD-tree functions are not working
    enum { has_explicit_dim = false };

    static inline __device__ __host__
    float3 get_point(const Photon &data) { return data.pos; }

    static inline __device__ __host__
    float get_coord(const Photon &data, int dim)
    { return cukd::get_coord(get_point(data),dim); }

    // "Optimized" KD-tree functions
    static inline __device__ int get_dim(const Photon &p)
    { return p.split_dim; }

    static inline __device__ void set_dim(Photon &p, int dim)
    { p.split_dim = dim; }
};

/* variables for the ray generation program */
struct RayGenData
{
    uint32_t *fbPtr;
    owl::vec2i  fbSize;
    OptixTraversableHandle world;
    owl::vec3f sky_color;

    LightSource* lights;
    int numLights;
    Photon* photons;
    int numPhotons;

    struct {
        owl::vec3f pos;
        owl::vec3f dir_00; // out-of-screen
        owl::vec3f dir_du; // left-to-right
        owl::vec3f dir_dv; // bottom-to-top
    } camera;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_color;
};

