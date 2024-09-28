#include <iostream>
#include <fstream>
#include <vector>
#include <string>
// public owl node-graph API
#include "owl/owl.h"
// our device-side data structures
#include "../include/deviceCode.h"
// external helper stuff for image output
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../../common/src/assetImporter.h"
#include "../../externals/assimp/code/AssetLib/Q3BSP/Q3BSPFileData.h"
#include "../../externals/stb/stb_image_write.h"
#include "assimp/Importer.hpp"
#include "../include/program.h"
#include "../../common/src/common.h"
#include <cukd/builder.h>

constexpr owl3f sky_color = owl3f { 255./255., 255./255., 255./255. };

/* Image configuration */
auto outFileName = "result.png";
const owl::vec2i fbSize(800,600);
const owl::vec3f lookFrom(80.f,30.f,0.f);
const owl::vec3f lookAt(10.f,20.f,0.f);
const owl::vec3f lookUp(0.f,-1.f,0.f);
const float aspect = fbSize.x / static_cast<float>(fbSize.y);
constexpr float cosFovy = 0.66f;
constexpr float fovy = 0.87f;

extern "C" char deviceCode_ptx[];

Photon* readPhotonsFromFile(const std::string& filename, int& count) {
  std::ifstream file(filename);
  std::vector<Photon> tempPhotons;

  if (!file.is_open()) {
    std::cerr << "Error opening file: " << filename << std::endl;
    count = 0;
    return nullptr;
  }

  Photon photon;
  while (file >> photon.pos.x >> photon.pos.y >> photon.pos.z
              >> photon.dir.x >> photon.dir.y >> photon.dir.z
              >> photon.color.x >> photon.color.y >> photon.color.z) {
    tempPhotons.push_back(photon);
  }

  count = tempPhotons.size();
  if (count == 0) {
    return nullptr;
  }

  Photon* photonArray = new Photon[count];
  std::copy(tempPhotons.begin(), tempPhotons.end(), photonArray);

  return photonArray;
}

void loadPhotons(Program &program) {
  auto photonsFromFile = readPhotonsFromFile("photons.txt", program.numPhotons);
  program.photonsBuffer = owlDeviceBufferCreate(program.owlContext, OWL_USER_TYPE(Photon), program.numPhotons, photonsFromFile);

  Photon* photons;
  CUKD_CUDA_CALL(MallocManaged((void **) &photons, program.numPhotons * sizeof(Photon)));
  for (int i=0; i < program.numPhotons; i++) {
    photons[i].pos = photonsFromFile[i].pos;
    photons[i].dir = photonsFromFile[i].dir;
    photons[i].color = photonsFromFile[i].color;
  }
  cukd::buildTree<Photon,Photon_traits>(photons,program.numPhotons);
}

void setupCamera(Program &program) {
  program.camera.pos = lookFrom;
  program.camera.dir_00 = normalize(lookAt-lookFrom);
  program.camera.dir_du = cosFovy * aspect * normalize(cross(program.camera.dir_00, lookUp));
  program.camera.dir_dv = cosFovy * normalize(cross(program.camera.dir_du, program.camera.dir_00));
  program.camera.dir_00 -= 0.5f * (program.camera.dir_du + program.camera.dir_dv);
}

void loadLights(Program &program, const std::unique_ptr<World> &world) {
  program.numLights = static_cast<int>(world->light_sources.size());
  program.lightsBuffer =  owlDeviceBufferCreate(program.owlContext, OWL_USER_TYPE(LightSource),world->light_sources.size(), world->light_sources.data());
}

void setupMissProgram(Program &program) {
  OWLVarDecl missProgVars[] = {
          { "sky_color", OWL_FLOAT3, OWL_OFFSETOF(MissProgData, sky_color)},
          { /* sentinel to mark end of list */ }
  };

  auto missProg = owlMissProgCreate(program.owlContext,program.owlModule,"miss",sizeof(MissProgData),missProgVars,-1);
  auto shadowMissProg = owlMissProgCreate(program.owlContext,program.owlModule,"shadow",0,nullptr,-1);

  owlMissProgSet3f(missProg,"sky_color", sky_color);
}

void setupClosestHitProgram(Program &program) {
  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType,0,program.owlModule,"TriangleMesh");
  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType,1,program.owlModule,"shadow");
}

void setupRaygenProgram(Program &program) {
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
          { "numLights",     OWL_INT,         OWL_OFFSETOF(RayGenData,numLights)},
          { "photons",      OWL_BUFPTR,       OWL_OFFSETOF(RayGenData,photons)},
          { "numPhotons",   OWL_INT,          OWL_OFFSETOF(RayGenData,numPhotons)},
          { /* sentinel to mark end of list */ }
  };

  program.rayGen = owlRayGenCreate(program.owlContext,program.owlModule,"simpleRayGen",
                           sizeof(RayGenData),
                           rayGenVars,-1);

  // ----------- set variables  ----------------------------
  owlRayGenSetBuffer(program.rayGen,"fbPtr",        program.frameBuffer);
  owlRayGenSet2i    (program.rayGen,"fbSize",       reinterpret_cast<const owl2i&>(program.frameBufferSize));
  owlRayGenSetGroup (program.rayGen,"world",        program.geometryData.worldGroup);
  owlRayGenSet3f    (program.rayGen,"camera.pos",   reinterpret_cast<const owl3f&>(program.camera.pos));
  owlRayGenSet3f    (program.rayGen,"camera.dir_00",reinterpret_cast<const owl3f&>(program.camera.dir_00));
  owlRayGenSet3f    (program.rayGen,"camera.dir_du",reinterpret_cast<const owl3f&>(program.camera.dir_du));
  owlRayGenSet3f    (program.rayGen,"camera.dir_dv",reinterpret_cast<const owl3f&>(program.camera.dir_dv));
  owlRayGenSet3f    (program.rayGen,"sky_color",    sky_color);
  owlRayGenSetBuffer(program.rayGen,"lights",       program.lightsBuffer);
  owlRayGenSet1i    (program.rayGen,"numLights",    program.numLights);
  owlRayGenSetBuffer(program.rayGen,"photons",      program.photonsBuffer);
  owlRayGenSet1i    (program.rayGen,"numPhotons",   program.numPhotons);
}

int main(int ac, char **av)
{
  LOG("Starting up...");

  auto *ai_importer = new Assimp::Importer;
  std::string path = "../assets/models/dragon/dragon-box.glb";
  auto world =  assets::import_scene(ai_importer, path);

  LOG_OK("Loaded world.");

  Program program;
  program.owlContext = owlContextCreate(nullptr,1);
  program.owlModule = owlModuleCreate(program.owlContext, deviceCode_ptx);
  owlContextSetRayTypeCount(program.owlContext, 2);

  program.frameBufferSize = fbSize;
  program.frameBuffer = owlHostPinnedBufferCreate(program.owlContext,OWL_INT,fbSize.x * fbSize.y);

  program.geometryData = loadGeometry(program.owlContext, world);

  loadLights(program, world);
  loadPhotons(program);
  setupCamera(program);

  setupMissProgram(program);
  setupClosestHitProgram(program);
  setupRaygenProgram(program);

  owlBuildPrograms(program.owlContext);
  owlBuildPipeline(program.owlContext);
  owlBuildSBT(program.owlContext);

  owlRayGenLaunch2D(program.rayGen, program.frameBufferSize.x, program.frameBufferSize.y);

  auto *fb = static_cast<const uint32_t*>(owlBufferGetPointer(program.frameBuffer, 0));
  stbi_write_png(outFileName,fbSize.x,fbSize.y,4,fb,fbSize.x*sizeof(uint32_t));

  owlContextDestroy(program.owlContext);

  return 0;
}
