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

void loadPhotons(Program &program, const std::string& filename) {
  auto photonsFromFile = readPhotonsFromFile(filename, program.numPhotons);
  CUKD_CUDA_CALL(MallocManaged((void **) &program.photonsBuffer, program.numPhotons * sizeof(Photon)));
  for (int i=0; i < program.numPhotons; i++) {
    program.photonsBuffer[i].pos = photonsFromFile[i].pos;
    program.photonsBuffer[i].dir = photonsFromFile[i].dir;
    program.photonsBuffer[i].color = photonsFromFile[i].color;
  }
  cukd::buildTree<Photon,Photon_traits>(program.photonsBuffer,program.numPhotons);
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

  owlMissProgSet3f(missProg, "sky_color", reinterpret_cast<const owl3f&>(sky_color));
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
          { "lights",        OWL_BUFPTR,      OWL_OFFSETOF(RayGenData,lights)},
          { "numLights",     OWL_INT,         OWL_OFFSETOF(RayGenData,numLights)},
          { "photons",      OWL_RAW_POINTER,  OWL_OFFSETOF(RayGenData,photons)},
          { "numPhotons",   OWL_INT,          OWL_OFFSETOF(RayGenData,numPhotons)},
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
  owlRayGenSetPointer(program.rayGen,"photons",      program.photonsBuffer);
  owlRayGenSet1i    (program.rayGen,"numPhotons",   program.numPhotons);
  owlRayGenSet1i    (program.rayGen,"samples_per_pixel", program.samplesPerPixel);
  owlRayGenSet1i    (program.rayGen,"max_ray_depth", program.maxDepth);
}

int main(int ac, char **av)
{
  LOG("Starting up...")

  Program program;
  program.owlContext = owlContextCreate(nullptr,1);
  program.owlModule = owlModuleCreate(program.owlContext, deviceCode_ptx);
  owlContextSetRayTypeCount(program.owlContext, 2);

  LOG("Loading Config file...")

  auto cfg = parse_config();

  auto photons_filename = cfg["data"]["photons_file"].as_string();
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
  loadPhotons(program, photons_filename);
  setupCamera(program, lookFrom, lookAt, lookUp, fovy);

  setupMissProgram(program, sky_colour);
  setupClosestHitProgram(program);
  setupRaygenProgram(program);

  owlBuildPrograms(program.owlContext);
  owlBuildPipeline(program.owlContext);
  owlBuildSBT(program.owlContext);

  LOG_OK("Launching...");

  owlRayGenLaunch2D(program.rayGen, program.frameBufferSize.x, program.frameBufferSize.y);

  LOG_OK("Saving image...");

  auto *fb = static_cast<const uint32_t*>(owlBufferGetPointer(program.frameBuffer, 0));
  stbi_write_png(output_filename.c_str(),program.frameBufferSize.x,program.frameBufferSize.y,4,fb,program.frameBufferSize.x*sizeof(uint32_t));

  owlContextDestroy(program.owlContext);
  LOG_OK("Finished. If all went well, this should be the last output.");

  return 0;
}
