// ======================================================================== //
// Copyright 2019 Ingo Wald                                                 //
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

// This program sets up a single geometric object, a mesh for a cube, and
// its acceleration structure, then ray traces it.

// public owl node-graph API
#include "owl/owl.h"
// our device-side data structures
#include "../cuda/deviceCode.h"
// external helper stuff for image output
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "assetImporter.h"
#include "../../externals/assimp/code/AssetLib/Q3BSP/Q3BSPFileData.h"
#include "../../externals/stb/stb_image_write.h"
#include "assimp/Importer.hpp"

#define LOG(message)                                            \
  std::cout << OWL_TERMINAL_BLUE;                               \
  std::cout << "#owl.sample(main): " << message << std::endl;   \
  std::cout << OWL_TERMINAL_DEFAULT;
#define LOG_OK(message)                                         \
  std::cout << OWL_TERMINAL_LIGHT_BLUE;                         \
  std::cout << "#owl.sample(main): " << message << std::endl;   \
  std::cout << OWL_TERMINAL_DEFAULT;

/* Image configuration */
auto outFileName = "result.png";
const owl::vec2i fbSize(800,600);
const owl::vec3f lookFrom(-3.f,50.f,-3.f);
const owl::vec3f lookAt(-3.f,-5.f,-3.f);
const owl::vec3f lookUp(-1.f,0.f,0.f);
constexpr float cosFovy = 0.66f;

extern "C" char deviceCode_ptx[];

int main(int ac, char **av)
{
  LOG("Starting up...");
  auto *ai_importer = new Assimp::Importer;
  std::string path = "../assets/models/one-cube/cube.obj";
  auto world =  assets::import_scene(ai_importer, path);

  LOG_OK("Loaded world.");

  // create a context on the first device:
  OWLContext context = owlContextCreate(nullptr,1);
  OWLModule module = owlModuleCreate(context, deviceCode_ptx);

  // ##################################################################
  // set up all the *GEOMETRY* graph we want to render
  // ##################################################################

  // -------------------------------------------------------
  // declare geometry type
  // -------------------------------------------------------

  OWLVarDecl trianglesGeomVars[] = {
    { "index",  OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,index)},
    { "vertex", OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,vertex)},
    { "material", OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,material)},
    { nullptr /* Sentinel to mark end-of-list */}
  };

  OWLGeomType trianglesGeomType
    = owlGeomTypeCreate(context,
                        OWL_TRIANGLES,
                        sizeof(TrianglesGeomData),
                        trianglesGeomVars,-1);
  owlGeomTypeSetClosestHit(trianglesGeomType,0,
                           module,"TriangleMesh");

  // ##################################################################
  // set up all the *GEOMS* we want to run that code on
  // ##################################################################

  LOG("building geometries ...");

  // ------------------------------------------------------------------
  // triangle mesh
  // ------------------------------------------------------------------
  OWLBuffer frameBuffer
  = owlHostPinnedBufferCreate(context,OWL_INT,fbSize.x*fbSize.y);

  std::vector<OWLGeom> geoms;
  const int numMeshes = static_cast<int>(world->meshes.size());

  for (int meshID=0; meshID<numMeshes; meshID++) {
    auto [vertices, indices, material] = world->meshes[meshID];
    std::cout << "ID: " << meshID << " | mat: " << material->albedo << '\n';
    for (const auto & v : vertices)
      std::cout << "v " << v << '\n';

    for (const auto & i : indices)
      std::cout << "v " << i << '\n';


    std::vector mats_vec = { *material };

    OWLBuffer vertexBuffer
      = owlDeviceBufferCreate(context,OWL_FLOAT3,vertices.size(), vertices.data());
    OWLBuffer indexBuffer
      = owlDeviceBufferCreate(context,OWL_INT3,indices.size(), indices.data());
    OWLBuffer materialBuffer
      = owlDeviceBufferCreate(context,OWL_USER_TYPE(Material),1, mats_vec.data());

    OWLGeom trianglesGeom
      = owlGeomCreate(context,trianglesGeomType);

    owlTrianglesSetVertices(trianglesGeom,vertexBuffer,
                            vertices.size(),sizeof(owl::vec3f),0);
    owlTrianglesSetIndices(trianglesGeom,indexBuffer,
                           indices.size(),sizeof(owl::vec3i),0);

    owlGeomSetBuffer(trianglesGeom,"vertex",vertexBuffer);
    owlGeomSetBuffer(trianglesGeom,"index",indexBuffer);
    owlGeomSetBuffer(trianglesGeom,"material", materialBuffer);

    geoms.push_back(trianglesGeom);
  }

  // ------------------------------------------------------------------
  // the group/accel for that mesh
  // ------------------------------------------------------------------
  OWLGroup trianglesGroup
    = owlTrianglesGeomGroupCreate(context,geoms.size(),geoms.data());
  owlGroupBuildAccel(trianglesGroup);
  OWLGroup owl_world
    = owlInstanceGroupCreate(context,1);
  owlInstanceGroupSetChild(owl_world,0,trianglesGroup);
  owlGroupBuildAccel(owl_world);


  // ##################################################################
  // set miss and raygen program required for SBT
  // ##################################################################

  // -------------------------------------------------------
  // set up miss prog
  // -------------------------------------------------------
  owl::vec3f sky_colour = { 42./255., 169./255., 238./255. };
  OWLVarDecl missProgVars[]
    = {
    { "sky_color", OWL_FLOAT3, OWL_OFFSETOF(MissProgData, sky_color)},
    { /* sentinel to mark end of list */ }
  };

  // ----------- create object  ----------------------------
  OWLMissProg missProg
    = owlMissProgCreate(context,module,"miss",sizeof(MissProgData),
                        missProgVars,-1);

  // ----------- set variables  ----------------------------
  owlMissProgSet3f(missProg,"sky_color", owl3f {42./255., 169./255., 238./255.});

  // -------------------------------------------------------
  // set up ray gen program
  // -------------------------------------------------------
  OWLVarDecl rayGenVars[] = {
    { "fbPtr", OWL_BUFPTR, OWL_OFFSETOF(RayGenData,fbPtr)},
    { "fbSize", OWL_INT2,   OWL_OFFSETOF(RayGenData,fbSize)},
    { "world", OWL_GROUP,  OWL_OFFSETOF(RayGenData,world)},
    { "camera.origin", OWL_FLOAT3, OWL_OFFSETOF(RayGenData,camera.origin)},
    { "camera.lower_left_corner", OWL_FLOAT3, OWL_OFFSETOF(RayGenData,camera.lower_left_corner)},
    { "camera.horizontal", OWL_FLOAT3, OWL_OFFSETOF(RayGenData,camera.horizontal)},
    { "camera.vertical", OWL_FLOAT3, OWL_OFFSETOF(RayGenData,camera.vertical)},
    { /* sentinel to mark end of list */ }
  };

  // ----------- create object  ----------------------------
  OWLRayGen rayGen
    = owlRayGenCreate(context,module,"simpleRayGen",
                      sizeof(RayGenData),
                      rayGenVars,-1);

  // ----------- compute variable values  ------------------
  const float vfov = acos(cosFovy);
  const owl::vec3f vup = lookUp;
  const float aspect = fbSize.x / float(fbSize.y);
  const float theta = vfov * ((float)M_PI) / 180.0f;
  const float half_height = tanf(theta / 2.0f);
  const float half_width = aspect * half_height;
  const float focusDist = 10.f;
  const owl::vec3f origin = lookFrom;
  const owl::vec3f w = normalize(lookFrom - lookAt);
  const owl::vec3f u = normalize(cross(vup, w));
  const owl::vec3f v = cross(w, u);
  const owl::vec3f lower_left_corner
    = origin - half_width * focusDist*u - half_height * focusDist*v - focusDist * w;
  const owl::vec3f horizontal = 2.0f*half_width*focusDist*u;
  const owl::vec3f vertical = 2.0f*half_height*focusDist*v;

  // ----------- set variables  ----------------------------
  owlRayGenSetBuffer(rayGen,"fbPtr",        frameBuffer);
  owlRayGenSet2i    (rayGen,"fbSize",       reinterpret_cast<const owl2i&>(fbSize));
  owlRayGenSetGroup (rayGen,"world",        owl_world);
  owlRayGenSet3f    (rayGen,"camera.origin",   reinterpret_cast<const owl3f&>(origin));
  owlRayGenSet3f    (rayGen,"camera.lower_left_corner",reinterpret_cast<const owl3f&>(lower_left_corner));
  owlRayGenSet3f    (rayGen,"camera.horizontal",reinterpret_cast<const owl3f&>(horizontal));
  owlRayGenSet3f    (rayGen,"camera.vertical",reinterpret_cast<const owl3f&>(vertical));

  // ##################################################################
  // build *SBT* required to trace the groups
  // ##################################################################
  owlBuildPrograms(context);
  owlBuildPipeline(context);
  owlBuildSBT(context);

  // ##################################################################
  // now that everything is ready: launch it ....
  // ##################################################################

  LOG("launching ...");
  owlRayGenLaunch2D(rayGen,fbSize.x,fbSize.y);

  LOG("done with launch, writing picture ...");
  // for host pinned mem it doesn't matter which device we query...
  auto *fb = static_cast<const uint32_t*>(owlBufferGetPointer(frameBuffer, 0));
  assert(fb);
  stbi_write_png(outFileName,fbSize.x,fbSize.y,4,
                 fb,fbSize.x*sizeof(uint32_t));
  LOG_OK("written rendered frame buffer to file "<<outFileName);
  // ##################################################################
  // and finally, clean up
  // ##################################################################

  LOG("destroying devicegroup ...");
  owlContextDestroy(context);

  LOG_OK("seems all went OK; app is done, this should be the last output ...");
  return 0;
}
