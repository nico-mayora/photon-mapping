#include <iostream>
#include <fstream>
#include <vector>
#include <string>
// public owl node-graph API
#include "owl/owl.h"
// our device-side data structures
#include "../cuda/deviceCode.h"
// external helper stuff for image output
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../../common/src/assetImporter.h"
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

constexpr owl3f sky_color = owl3f { 255./255., 255./255., 255./255. };

/* Image configuration */
auto outFileName = "result.png";
const owl::vec2i fbSize(800,600);
const owl::vec3f lookFrom(80.f,30.f,0.f);
const owl::vec3f lookAt(10.f,20.f,0.f);
const owl::vec3f lookUp(0.f,-1.f,0.f);
constexpr float cosFovy = 0.66f;

extern "C" char deviceCode_ptx[];

std::vector<Photon> readPhotonsFromFile(const std::string& filename) {
  std::ifstream file(filename);
  std::vector<Photon> photons;

  if (!file.is_open()) {
    std::cerr << "Error opening file: " << filename << std::endl;
    return photons;
  }

  Photon photon;
  while (file >> photon.pos.x >> photon.pos.y >> photon.pos.z
              >> photon.dir.x >> photon.dir.y >> photon.dir.z
              >> photon.color.x >> photon.color.y >> photon.color.z) {
    photons.push_back(photon);
  }

  file.close();
  return photons;
}

int main(int ac, char **av)
{
  LOG("Starting up...");
  auto *ai_importer = new Assimp::Importer;
  std::string path = "../assets/models/dragon/dragon-box.glb";
  auto world =  assets::import_scene(ai_importer, path);
  
  LOG_OK("Loaded world.");

  auto photons = readPhotonsFromFile("photons.txt");
  LOG_OK("Loaded photons.");

  // create a context on the first device:
  OWLContext context = owlContextCreate(nullptr,1);
  OWLModule module = owlModuleCreate(context, deviceCode_ptx);
  owlContextSetRayTypeCount(context, 2);

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
  owlGeomTypeSetClosestHit(trianglesGeomType,1,
                         module,"shadow");

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
//    auto [vertices, indices, material] = world->meshes[meshID];
    auto mesh = world->meshes[meshID];
    auto vertices = mesh.vertices;
    auto indices = mesh.indices;
    auto material = mesh.material;

    std::vector<Material> mats_vec = { *material };

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

  OWLBuffer light_sources_buffer =  owlDeviceBufferCreate(context,
    OWL_USER_TYPE(LightSource),world->light_sources.size(), world->light_sources.data());

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
  LOG("Setting up prog ...");

  // -------------------------------------------------------
  // set up miss prog
  // -------------------------------------------------------
  OWLVarDecl missProgVars[]
    = {
    { "sky_color", OWL_FLOAT3, OWL_OFFSETOF(MissProgData, sky_color)},
    { /* sentinel to mark end of list */ }
  };

  // ----------- create object  ----------------------------
  OWLMissProg missProg
    = owlMissProgCreate(context,module,"miss",sizeof(MissProgData),
                        missProgVars,-1);
  OWLMissProg missProgShadow
  = owlMissProgCreate(context,module,"shadow",
                      /* no sbt data: */0,nullptr,-1);

  // ----------- set variables  ----------------------------
  owlMissProgSet3f(missProg,"sky_color", sky_color);

  // -------------------------------------------------------
  // set up ray gen program
  // -------------------------------------------------------
  OWLVarDecl rayGenVars[] = {
    { "fbPtr",         OWL_BUFPTR,      OWL_OFFSETOF(RayGenData,fbPtr)},
    { "fbSize",        OWL_INT2,        OWL_OFFSETOF(RayGenData,fbSize)},
    { "world",         OWL_GROUP,       OWL_OFFSETOF(RayGenData,world)},
    { "camera.pos",    OWL_FLOAT3,      OWL_OFFSETOF(RayGenData,camera.pos)},
    { "camera.dir_00", OWL_FLOAT3,      OWL_OFFSETOF(RayGenData,camera.dir_00)},
    { "camera.dir_du", OWL_FLOAT3,      OWL_OFFSETOF(RayGenData,camera.dir_du)},
    { "camera.dir_dv", OWL_FLOAT3,      OWL_OFFSETOF(RayGenData,camera.dir_dv)},
    { "sky_color",     OWL_FLOAT3,      OWL_OFFSETOF(RayGenData,sky_color)},
    { "lights",        OWL_BUFPTR,      OWL_OFFSETOF(RayGenData,lights)},
    { "numLights",     OWL_INT, OWL_OFFSETOF(RayGenData,numLights)},
    { /* sentinel to mark end of list */ }
  };


  // ----------- create object  ----------------------------
  OWLRayGen rayGen
    = owlRayGenCreate(context,module,"simpleRayGen",
                      sizeof(RayGenData),
                      rayGenVars,-1);

  // ----------- compute variable values  ------------------
  owl::vec3f camera_pos = lookFrom;
  owl::vec3f camera_d00
    = normalize(lookAt-lookFrom);
  float aspect = fbSize.x / static_cast<float>(fbSize.y);
  owl::vec3f camera_ddu
    = cosFovy * aspect * normalize(cross(camera_d00,lookUp));
  owl::vec3f camera_ddv
    = cosFovy * normalize(cross(camera_ddu,camera_d00));
  camera_d00 -= 0.5f * camera_ddu;
  camera_d00 -= 0.5f * camera_ddv;
  int num_lights = static_cast<int>(world->light_sources.size());

  // ----------- set variables  ----------------------------
  owlRayGenSetBuffer(rayGen,"fbPtr",        frameBuffer);
  owlRayGenSet2i    (rayGen,"fbSize",       reinterpret_cast<const owl2i&>(fbSize));
  owlRayGenSetGroup (rayGen,"world",        owl_world);
  owlRayGenSet3f    (rayGen,"camera.pos",   reinterpret_cast<const owl3f&>(camera_pos));
  owlRayGenSet3f    (rayGen,"camera.dir_00",reinterpret_cast<const owl3f&>(camera_d00));
  owlRayGenSet3f    (rayGen,"camera.dir_du",reinterpret_cast<const owl3f&>(camera_ddu));
  owlRayGenSet3f    (rayGen,"camera.dir_dv",reinterpret_cast<const owl3f&>(camera_ddv));
  owlRayGenSet3f    (rayGen,"sky_color",    sky_color);
  owlRayGenSetBuffer(rayGen,"lights",       light_sources_buffer);
  owlRayGenSet1i    (rayGen,"numLights",    num_lights);

  LOG("building sbt...");

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
