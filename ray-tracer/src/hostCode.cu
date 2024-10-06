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
#include "../../externals/stb/stb_image_write.h"
#include "../../common/src/configLoader.h"
#include <assimp/Importer.hpp>
#include "../include/program.h"
#include "../../common/src/common.h"
#include <cukd/builder.h>
#include <cukd/knn.h>
#include <chrono>

#define PHOTON_POWER (1.f)
#define CAUSTICS_PHOTON_POWER (float(PHOTON_POWER) * 0.5f)

extern "C" char deviceCode_ptx[];

Photon* readPhotonsFromFile(const std::string& filename, int& count) {
  std::ifstream file(filename);
  std::vector<Photon> tempPhotons;

  if (!file.is_open()) {
    std::cerr << "Error opening file: " << filename << std::endl;
    count = 0;
    return nullptr;
  }

  Photon photon{};
  while (file >> photon.pos.x >> photon.pos.y >> photon.pos.z
              >> photon.dir.x >> photon.dir.y >> photon.dir.z
              >> photon.color.x >> photon.color.y >> photon.color.z) {
    tempPhotons.push_back(photon);
  }

  count = tempPhotons.size();
  if (count == 0) {
    return nullptr;
  }

  auto* photonArray = new Photon[count];
  std::copy(tempPhotons.begin(), tempPhotons.end(), photonArray);

  return photonArray;
}

void loadPhotons(Program &program, const std::string& globalPhotonsFilename, const std::string& causticsPhotonsFilename) {
  int nonCausticPhotonsNum = 0;
  auto globalPhotonsFromFile = readPhotonsFromFile(globalPhotonsFilename, nonCausticPhotonsNum);
  auto causticPhotonsFromFile = readPhotonsFromFile(causticsPhotonsFilename, program.numCausticPhotons);
  program.numGlobalPhotons = nonCausticPhotonsNum + program.numCausticPhotons;
  printf("Loaded %d photons (non-caustic %d, caustic %d)\n.", program.numGlobalPhotons, nonCausticPhotonsNum, program.numCausticPhotons);

  CUKD_CUDA_CALL(MallocManaged((void **)&program.causticPhotons, program.numCausticPhotons * sizeof(Photon)));
  CUKD_CUDA_CALL(MallocManaged((void **)&program.globalPhotons,  program.numGlobalPhotons  * sizeof(Photon)));

  // Load in non Caustic photons to global map
  for (int i=0; i < nonCausticPhotonsNum; i++) {
    program.globalPhotons[i].pos = globalPhotonsFromFile[i].pos;
    program.globalPhotons[i].dir = globalPhotonsFromFile[i].dir;
    program.globalPhotons[i].color = globalPhotonsFromFile[i].color;
    program.globalPhotons[i].power = PHOTON_POWER;
  }

  // Load caustic photons to both maps
  for (int k=0; k < program.numCausticPhotons; k++) {
    program.causticPhotons[k].pos   = causticPhotonsFromFile[k].pos;
    program.causticPhotons[k].dir   = causticPhotonsFromFile[k].dir;
    program.causticPhotons[k].color = causticPhotonsFromFile[k].color;
    program.causticPhotons[k].power = CAUSTICS_PHOTON_POWER;

    program.globalPhotons[nonCausticPhotonsNum+k].pos   = causticPhotonsFromFile[k].pos;
    program.globalPhotons[nonCausticPhotonsNum+k].dir   = causticPhotonsFromFile[k].dir;
    program.globalPhotons[nonCausticPhotonsNum+k].color = causticPhotonsFromFile[k].color;
    program.globalPhotons[nonCausticPhotonsNum+k].power = CAUSTICS_PHOTON_POWER;
  }

  cukd::box_t<float3> *globalWorldBounds = NULL;
  CUKD_CUDA_CALL(MallocManaged((void **)&globalWorldBounds,sizeof(*globalWorldBounds)));

  cukd::box_t<float3> *causticWorldBounds = NULL;
  CUKD_CUDA_CALL(MallocManaged((void **)&causticWorldBounds,sizeof(*causticWorldBounds)));

  program.globalPhotonsBounds = globalWorldBounds;
  program.causticPhotonsBounds = causticWorldBounds;
  auto startKDT = std::chrono::high_resolution_clock::now();
  cukd::buildTree<Photon,Photon_traits>(program.globalPhotons,program.numGlobalPhotons, program.globalPhotonsBounds);
  cukd::buildTree<Photon,Photon_traits>(program.causticPhotons,program.numCausticPhotons, program.causticPhotonsBounds);
  auto endKDT = std::chrono::high_resolution_clock::now();
  auto durationKDT = std::chrono::duration_cast<std::chrono::milliseconds>(endKDT - startKDT);
  printf("Time taken to build KD-Tree: %d ms\n", durationKDT.count());
}
void setupCamera(Program &program, const owl::vec3f &lookFrom, const owl::vec3f &lookAt, const owl::vec3f &lookUp, float fovy) {
  const float aspect = program.frameBufferSize.x / static_cast<float>(program.frameBufferSize.y);
  const float cosFovy = std::cos(fovy);
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

void setupMissProgram(Program &program, const owl::vec3f &sky_color) {
  OWLVarDecl missProgVars[] = {
          { "sky_color", OWL_FLOAT3, OWL_OFFSETOF(MissProgData, sky_colour)},
          { /* sentinel to mark end of list */ }
  };

  auto missProg = owlMissProgCreate(program.owlContext,program.owlModule,"miss",sizeof(MissProgData),missProgVars,-1);
  auto shadowMissProg = owlMissProgCreate(program.owlContext,program.owlModule,"shadow",0,nullptr,-1);
  auto diffuseMissProg = owlMissProgCreate(program.owlContext,program.owlModule,"ScatterDiffuse",0,nullptr,-1);

  owlMissProgSet3f(missProg, "sky_color", reinterpret_cast<const owl3f&>(sky_color));
}

void setupClosestHitProgram(Program &program) {
  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType,PRIMARY,program.owlModule,"TriangleMesh");
  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType,SHADOW,program.owlModule,"shadow");
  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType,DIFFUSE,program.owlModule,"ScatterDiffuse");
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
          { "lights",        OWL_BUFPTR,      OWL_OFFSETOF(RayGenData,lights)},
          { "numLights",     OWL_INT,         OWL_OFFSETOF(RayGenData,numLights)},
          { "globalPhotons",      OWL_RAW_POINTER,  OWL_OFFSETOF(RayGenData,globalPhotons)},
          { "globalPhotonsBounds", OWL_RAW_POINTER,  OWL_OFFSETOF(RayGenData,globalPhotonsBounds)},
          { "numGlobalPhotons",   OWL_INT,          OWL_OFFSETOF(RayGenData,numGlobalPhotons)},
          { "causticPhotons",      OWL_RAW_POINTER,  OWL_OFFSETOF(RayGenData,causticPhotons)},
          { "causticPhotonsBounds", OWL_RAW_POINTER,  OWL_OFFSETOF(RayGenData,causticPhotonsBounds)},
          { "numCausticPhotons",   OWL_INT,          OWL_OFFSETOF(RayGenData,numCausticPhotons)},
          { "samples_per_pixel", OWL_INT,     OWL_OFFSETOF(RayGenData,samples_per_pixel)},
          { "max_ray_depth", OWL_INT,         OWL_OFFSETOF(RayGenData,max_ray_depth)},
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
  owlRayGenSetBuffer(program.rayGen,"lights",       program.lightsBuffer);
  owlRayGenSet1i    (program.rayGen,"numLights",    program.numLights);
  owlRayGenSetPointer(program.rayGen,"globalPhotons",     program.globalPhotons);
  owlRayGenSetPointer(program.rayGen,"globalPhotonsBounds",program.globalPhotonsBounds);
  owlRayGenSet1i    (program.rayGen,"numGlobalPhotons",   program.numGlobalPhotons);
  owlRayGenSetPointer(program.rayGen,"causticPhotons",    program.causticPhotons);
  owlRayGenSetPointer(program.rayGen,"causticPhotonsBounds",program.causticPhotonsBounds);
  owlRayGenSet1i    (program.rayGen,"numCausticPhotons",  program.numCausticPhotons);
  owlRayGenSet1i    (program.rayGen,"samples_per_pixel", program.samplesPerPixel);
  owlRayGenSet1i    (program.rayGen,"max_ray_depth", program.maxDepth);
}

int main(int ac, char **av)
{
  LOG("Starting up...")

  Program program;
  program.owlContext = owlContextCreate(nullptr,1);
  program.owlModule = owlModuleCreate(program.owlContext, deviceCode_ptx);
  owlContextSetRayTypeCount(program.owlContext, RAY_TYPES_COUNT);

  LOG("Loading Config file...")

  auto cfg = parse_config();

  auto global_photons_filename = cfg["data"]["photons_file"].as_string();
  auto caustics_photons_filename = cfg["data"]["caustics_photons_file"].as_string();
  auto model_path = cfg["data"]["model_path"].as_string();

  auto lookAt = toml_to_vec3f(cfg["camera"]["look_at"]);
  auto lookFrom = toml_to_vec3f(cfg["camera"]["look_from"]);
  auto lookUp = toml_to_vec3f(cfg["camera"]["look_up"]);
  float fovy = static_cast<float>(cfg["camera"]["fovy"].as_floating());

  auto sky_colour = toml_to_vec3f(cfg["ray-tracer"]["sky_colour"]);
  auto output_filename = cfg["ray-tracer"]["output_filename"].as_string();
  program.frameBufferSize = toml_to_vec2i(cfg["ray-tracer"]["fb_size"]);
  program.samplesPerPixel = static_cast<int>(cfg["ray-tracer"]["samples_per_pixel"].as_integer());
  program.maxDepth = static_cast<int>(cfg["ray-tracer"]["depth"].as_integer());

  auto *ai_importer = new Assimp::Importer;
  auto world =  assets::import_scene(ai_importer, model_path);

  LOG_OK("Loaded world.");

  LOG_OK("Setting up programs...");

  program.frameBuffer = owlHostPinnedBufferCreate(program.owlContext,OWL_INT,program.frameBufferSize.x * program.frameBufferSize.y);
  program.geometryData = loadGeometry(program.owlContext, world);

  loadLights(program, world);
  loadPhotons(program, global_photons_filename, caustics_photons_filename);
  setupCamera(program, lookFrom, lookAt, lookUp, fovy);

  setupMissProgram(program, sky_colour);
  setupClosestHitProgram(program);
  setupRaygenProgram(program);

  owlBuildPrograms(program.owlContext);
  owlBuildPipeline(program.owlContext);
  owlBuildSBT(program.owlContext);

  LOG_OK("Launching...");
  auto startRT = std::chrono::high_resolution_clock::now();
  owlRayGenLaunch2D(program.rayGen, program.frameBufferSize.x, program.frameBufferSize.y);
  auto endRT = std::chrono::high_resolution_clock::now();
  LOG_OK("Saving image...");

  auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endRT - startRT);
  printf("Time taken to render: %d ms\n", duration.count());

  auto *fb = static_cast<const uint32_t*>(owlBufferGetPointer(program.frameBuffer, 0));
  stbi_write_png(output_filename.c_str(),program.frameBufferSize.x,program.frameBufferSize.y,4,fb,program.frameBufferSize.x*sizeof(uint32_t));

  owlContextDestroy(program.owlContext);
  LOG_OK("Finished. If all went well, this should be the last output.");

  return 0;
}
