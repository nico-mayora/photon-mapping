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
#include "../include/context.h"
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

extern "C" char deviceCode_ptx[];

int main(int ac, char **av)
{
  LOG("Starting up...");

  auto *ai_importer = new Assimp::Importer;
  std::string path = "../assets/models/dragon/dragon-box.glb";
  auto world =  assets::import_scene(ai_importer, path);

  LOG_OK("Loaded world.");

  PhotonViewer program(deviceCode_ptx, fbSize);

  program.loadGeometry(world);
  program.loadLights(world);
  program.loadPhotons("photons.txt");
  program.setupCamera(lookFrom, lookAt, lookUp, aspect, cosFovy);

  program.setupMissProgram();
  program.setupClosestHitProgram();
  program.setupRaygenProgram();

  program.build();
  program.run();

  auto *fb = static_cast<const uint32_t*>(owlBufferGetPointer(program.frameBuffer, 0));
  stbi_write_png(outFileName,fbSize.x,fbSize.y,4,fb,fbSize.x*sizeof(uint32_t));

  program.destroy();

  return 0;
}
