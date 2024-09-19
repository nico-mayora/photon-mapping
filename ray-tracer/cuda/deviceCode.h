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

/* We store the MaterialType to correctly pick the BSDF when reflecting incident rays. */
enum MaterialType {
    LAMBERTIAN,
    SPECULAR,
    GLASS,
};

struct Material {
    MaterialType surface_type;
    owl::vec3f albedo;
    double reflectivity; // higher = more reflective
    double refraction_idx;
};

enum LightType {
    POINT_LIGHT,
    SQUARE_LIGHT,
};

struct LightSource {
    LightType source_type;
    owl::vec3f pos;
    double power;
    owl::vec3f rgb;
    /* for emission surface */
    owl::vec3f normal;
    double side_length;
};

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

    LightSource* lights;
    int numLights;

    struct {
        owl::vec3f pos;
        owl::vec3f dir_00; // out-of-screen
        owl::vec3f dir_du; // left-to-right
        owl::vec3f dir_dv; // bottom-to-top
    } camera;
};

typedef owl::LCG<> Random;

enum RayEvent {
    Scattered,
    Absorbed,
    Missed,
};

struct PerRayData {
    Random random;

    owl::vec3f colour;
    RayEvent event;
    struct {
        owl::vec3f s_origin;
        owl::vec3f s_direction;
        owl::vec3f normal_at_hitpoint;
    } scattered;
};

/* variables for the miss program */
struct MissProgData
{
    owl::vec3f  sky_color;
};

