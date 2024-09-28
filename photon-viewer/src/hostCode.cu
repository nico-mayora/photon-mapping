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

#define RGBA_BLACK 0xFF000000

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
  auto photons = readPhotonsFromFile("photons.txt", program.numPhotons);

  auto viewMatrix = glm::lookAt(glm::vec3(lookFrom.x, lookFrom.y, lookFrom.z),
                                glm::vec3(lookAt.x, lookAt.y, lookAt.z),
                                glm::vec3(lookUp.x, lookUp.y, lookUp.z));
  auto perspectiveMatrix = glm::perspective(fovy, aspect, 0.1f, 1000.f);
  auto projectionMatrix = perspectiveMatrix * viewMatrix;

  for (int i = 0; i < program.numPhotons; i++) {
    auto photon = &photons[i];
    auto screenPos = projectionMatrix * glm::vec4(photon->pos.x, photon->pos.y, photon->pos.z, 1.f);
    if (screenPos.z < 0) {
      photon->pixel.x = -1;
      photon->pixel.y = -1;
    }else {
      photon->pixel.x = static_cast<int>((screenPos.x / screenPos.w + 1.f) * 0.5f * fbSize.x);
      photon->pixel.y = static_cast<int>((screenPos.y / screenPos.w + 1.f) * 0.5f * fbSize.y);
    }
  }

  program.photonsBuffer = owlDeviceBufferCreate(program.owlContext, OWL_USER_TYPE(Photon), program.numPhotons, photons);
}

void setupCamera(Program &program) {
  program.camera.pos = lookFrom;
  program.camera.dir_00 = normalize(lookAt-lookFrom);
  program.camera.dir_du = cosFovy * aspect * normalize(cross(program.camera.dir_00, lookUp));
  program.camera.dir_dv = cosFovy * normalize(cross(program.camera.dir_du, program.camera.dir_00));
  program.camera.dir_00 -= 0.5f * (program.camera.dir_du + program.camera.dir_dv);
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
  owlRayGenSet3f(program.rayGen,"cameraPos",reinterpret_cast<const owl3f&>(program.camera.pos));
  owlRayGenSetBuffer(program.rayGen,"photons",program.photonsBuffer);
  owlRayGenSet1i(program.rayGen,"numPhotons",program.numPhotons);
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
  owlContextSetRayTypeCount(program.owlContext, 1);

  program.frameBufferSize = fbSize;
  program.frameBuffer = owlHostPinnedBufferCreate(program.owlContext,OWL_INT,fbSize.x * fbSize.y);

  int *initialFrameBuffer = new int[fbSize.x * fbSize.y];
  for (int i = 0; i < fbSize.x * fbSize.y; i++) {
    initialFrameBuffer[i] = RGBA_BLACK;
  }
  owlBufferUpload(program.frameBuffer,initialFrameBuffer);
  delete[] initialFrameBuffer;

  program.geometryData = loadGeometry(program.owlContext, world);

  loadPhotons(program);
  setupCamera(program);

  setupMissProgram(program);
  setupClosestHitProgram(program);
  setupRaygenProgram(program);

  owlBuildPrograms(program.owlContext);
  owlBuildPipeline(program.owlContext);
  owlBuildSBT(program.owlContext);

  owlRayGenLaunch2D(program.rayGen, program.numPhotons, 1);

  auto *fb = static_cast<const uint32_t*>(owlBufferGetPointer(program.frameBuffer, 0));
  stbi_write_png(outFileName,fbSize.x,fbSize.y,4,fb,fbSize.x*sizeof(uint32_t));

  owlContextDestroy(program.owlContext);

  return 0;
}