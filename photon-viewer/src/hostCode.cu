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
#include "glm/ext/matrix_transform.hpp"
#include "glm/ext/matrix_clip_space.hpp"
#include "../../common/src/configLoader.h"

#define RGBA_BLACK 0xFF000000

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

void loadPhotons(Program &program, const std::string& filename) {
  auto photons = readPhotonsFromFile(filename, program.numPhotons);

  auto viewMatrix = glm::lookAt(glm::vec3(program.camera.lookFrom.x, program.camera.lookFrom.y, program.camera.lookFrom.z),
                                glm::vec3(program.camera.lookAt.x, program.camera.lookAt.y, program.camera.lookAt.z),
                                glm::vec3(program.camera.lookUp.x, program.camera.lookUp.y, program.camera.lookUp.z));
  auto perspectiveMatrix = glm::perspective(program.camera.fovy, program.frameBufferSize.x / static_cast<float>(program.frameBufferSize.y), 0.1f, 1000.f);
  auto projectionMatrix = perspectiveMatrix * viewMatrix;

  for (int i = 0; i < program.numPhotons; i++) {
    auto photon = &photons[i];
    auto screenPos = projectionMatrix * glm::vec4(photon->pos.x, photon->pos.y, photon->pos.z, 1.f);
    if (screenPos.z < 0) {
      photon->pixel.x = -1;
      photon->pixel.y = -1;
    }else {
      photon->pixel.x = static_cast<int>((screenPos.x / screenPos.w + 1.f) * 0.5f * program.frameBufferSize.x);
      photon->pixel.y = program.frameBufferSize.y -  static_cast<int>((screenPos.y / screenPos.w + 1.f) * 0.5f * program.frameBufferSize.y);
    }
  }

  program.photonsBuffer = owlDeviceBufferCreate(program.owlContext, OWL_USER_TYPE(Photon), program.numPhotons, photons);
}

void setupMissProgram(Program &program) {
  owlMissProgCreate(program.owlContext,program.owlModule,"photonViewerMiss",0, nullptr,-1);
}

void setupClosestHitProgram(Program &program) {
  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType,0,program.owlModule,"photonViewerClosestHit");
}

void setupRaygenProgram(Program &program) {
  OWLVarDecl rayGenVars[] = {
{ "frameBuffer",OWL_BUFPTR,OWL_OFFSETOF(PhotonViewerRGD,frameBuffer)},
{ "frameBufferSize",OWL_INT2,OWL_OFFSETOF(PhotonViewerRGD,frameBufferSize)},
{ "world",OWL_GROUP,OWL_OFFSETOF(PhotonViewerRGD,world)},
{ "cameraPos",OWL_FLOAT3,OWL_OFFSETOF(PhotonViewerRGD,cameraPos)},
{ "photons",OWL_BUFPTR,OWL_OFFSETOF(PhotonViewerRGD,photons)},
{ "numPhotons",OWL_INT,OWL_OFFSETOF(PhotonViewerRGD,numPhotons)},
{ /* sentinel to mark end of list */ }
  };

  program.rayGen = owlRayGenCreate(program.owlContext,program.owlModule,"photonViewerRayGen",
                           sizeof(PhotonViewerRGD),
                           rayGenVars,-1);

  // ----------- set variables  ----------------------------
  owlRayGenSetBuffer(program.rayGen,"frameBuffer",program.frameBuffer);
  owlRayGenSet2i(program.rayGen,"frameBufferSize",reinterpret_cast<const owl2i&>(program.frameBufferSize));
  owlRayGenSetGroup(program.rayGen,"world",program.geometryData.worldGroup);
  owlRayGenSet3f(program.rayGen,"cameraPos",reinterpret_cast<const owl3f&>(program.camera.lookFrom));
  owlRayGenSetBuffer(program.rayGen,"photons",program.photonsBuffer);
  owlRayGenSet1i(program.rayGen,"numPhotons",program.numPhotons);
}

void run(toml::value &cfg, const std::string &photons_filename, const std::string &output_filename) {
  Program program;
  program.owlContext = owlContextCreate(nullptr,1);
  program.owlModule = owlModuleCreate(program.owlContext, deviceCode_ptx);
  owlContextSetRayTypeCount(program.owlContext, 1);

  program.camera.lookAt = toml_to_vec3f(cfg["camera"]["look_at"]);
  program.camera.lookFrom = toml_to_vec3f(cfg["camera"]["look_from"]);
  program.camera.lookUp = toml_to_vec3f(cfg["camera"]["look_up"]);
  program.camera.fovy = static_cast<float>(cfg["camera"]["fovy"].as_floating());

  program.frameBufferSize = toml_to_vec2i(cfg["photon-viewer"]["fb_size"]);
  program.frameBuffer = owlHostPinnedBufferCreate(program.owlContext,OWL_INT,program.frameBufferSize.x * program.frameBufferSize.y);

  auto *ai_importer = new Assimp::Importer;
  auto world =  assets::import_scene(ai_importer, cfg["data"]["model_path"].as_string());

  LOG_OK("Loaded world.");

  int frameBufferLength = program.frameBufferSize.x * program.frameBufferSize.y;
  int *initialFrameBuffer = new int[frameBufferLength];
  for (int i = 0; i < frameBufferLength; i++) {
    initialFrameBuffer[i] = RGBA_BLACK;
  }
  owlBufferUpload(program.frameBuffer,initialFrameBuffer);
  delete[] initialFrameBuffer;

  program.geometryData = loadGeometry(program.owlContext, world);

  loadPhotons(program, photons_filename);

  setupMissProgram(program);
  setupClosestHitProgram(program);
  setupRaygenProgram(program);

  owlBuildPrograms(program.owlContext);
  owlBuildPipeline(program.owlContext);
  owlBuildSBT(program.owlContext);

  owlRayGenLaunch2D(program.rayGen, program.numPhotons, 1);

  auto *fb = static_cast<const uint32_t*>(owlBufferGetPointer(program.frameBuffer, 0));
  stbi_write_png(output_filename.c_str(),program.frameBufferSize.x,program.frameBufferSize.y,4,fb,program.frameBufferSize.x*sizeof(uint32_t));

  owlContextDestroy(program.owlContext);
}

int main(int ac, char **av)
{
  LOG("Starting up...")
  LOG("Loading Config file...")

  auto cfg = parse_config();

  auto photons_filename = cfg["data"]["photons_file"].as_string();
  auto caustics_photons_filename = cfg["data"]["caustics_photons_file"].as_string();

  auto output_filename = cfg["photon-viewer"]["output_filename"].as_string();
  auto caustics_output_filename = cfg["photon-viewer"]["caustics_output_filename"].as_string();

  LOG("Running photon viewer...")
  run(cfg, photons_filename, output_filename);
  LOG_OK("Done with photon viewer.")

  LOG("Running caustics viewer...")
  run(cfg, caustics_photons_filename, caustics_output_filename);
  LOG_OK("Done with caustics viewer.")

  return 0;
}