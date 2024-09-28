#include <iostream>
#include <fstream>
#include <iomanip>
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

extern "C" char deviceCode_ptx[];

void writeAlivePhotons(const Photon* photons, int count, const std::string& filename) {
  std::ofstream outFile(filename);

  if (!outFile.is_open()) {
    std::cerr << "Error opening file: " << filename << std::endl;
    return;
  }

  outFile << std::fixed << std::setprecision(6);

  for (int i = 0; i < count; i++) {
    auto photon = photons[i];
    outFile << photon.pos.x << " " << photon.pos.y << " " << photon.pos.z << " "
            << photon.dir.x << " " << photon.dir.y << " " << photon.dir.z << " "
            << photon.color.x << " " << photon.color.y << " " << photon.color.z << "\n";
  }

  outFile.close();
}

void setupPointLightRayGenProgram(Program &program) {
  OWLVarDecl rayGenVars[] = {
          { "photons",OWL_BUFPTR,OWL_OFFSETOF(PointLightRGD,photons)},
          { "photonsCount",OWL_BUFPTR,OWL_OFFSETOF(PointLightRGD,photonsCount)},
          { "dims",OWL_INT2,OWL_OFFSETOF(PointLightRGD,dims)},
          { "world",OWL_GROUP,OWL_OFFSETOF(PointLightRGD,world)},
          { "position",OWL_FLOAT3,OWL_OFFSETOF(PointLightRGD,position)},
          { "color",OWL_FLOAT3,OWL_OFFSETOF(PointLightRGD,color)},
          { "intensity",OWL_FLOAT,OWL_OFFSETOF(PointLightRGD,intensity)},
          { /* sentinel to mark end of list */ }
  };

  program.rayGen = owlRayGenCreate(program.owlContext,program.owlModule,"pointLightRayGen",
                                   sizeof(PointLightRGD),
                                   rayGenVars,-1);

  owlRayGenSetBuffer(program.rayGen,"photons",program.photonsBuffer);
  owlRayGenSetBuffer(program.rayGen,"photonsCount",program.photonsCount);
  owlRayGenSetGroup(program.rayGen,"world",program.geometryData.worldGroup);
}

void setPointLightRayGenVariables(Program &program, const LightSource &light, owl::vec2i dims) {
  owlRayGenSet2i(program.rayGen,"dims",reinterpret_cast<const owl2i&>(dims));
  owlRayGenSet3f(program.rayGen,"position",reinterpret_cast<const owl3f&>(light.pos));
  owlRayGenSet3f(program.rayGen,"color",reinterpret_cast<const owl3f&>(light.rgb));
  owlRayGenSet1f(program.rayGen,"intensity",light.power);
}

int main(int ac, char **av)
{
  LOG("Starting up...");
  auto *ai_importer = new Assimp::Importer;
  std::string path = "../assets/models/dragon/dragon-box.glb";
  auto world =  assets::import_scene(ai_importer, path);
  double totalPower = 0;
  for (const auto & light : world->light_sources) {
    totalPower += light.power;
  }
  for (auto & light : world->light_sources) {
    light.num_photons = static_cast<int>(light.power / totalPower * MAX_PHOTONS);
  }

  Program program;

  program.owlContext = owlContextCreate(nullptr,1);
  program.owlModule = owlModuleCreate(program.owlContext, deviceCode_ptx);
  owlContextSetRayTypeCount(program.owlContext, 1);

  program.geometryData = loadGeometry(program.owlContext, world);

  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType, 0, program.owlModule,"triangleMeshClosestHit");
  owlMissProgCreate(program.owlContext, program.owlModule, "miss", 0, nullptr, -1);

  program.photonsBuffer = owlHostPinnedBufferCreate(program.owlContext,OWL_USER_TYPE(Photon),MAX_PHOTONS * MAX_RAY_BOUNCES);
  program.photonsCount = owlHostPinnedBufferCreate(program.owlContext, OWL_INT, 1);
  owlBufferClear(program.photonsCount);

  setupPointLightRayGenProgram(program);

  owlBuildPrograms(program.owlContext);
  owlBuildPipeline(program.owlContext);

  LOG("launching ...")

  for (auto light : world->light_sources) {
    setPointLightRayGenVariables(program, light, owl::vec2i (100, 100));

    owlBuildSBT(program.owlContext);

    owlRayGenLaunch2D(program.rayGen,100,100);
  }

  LOG("done with launch, writing picture ...")
  // for host pinned mem it doesn't matter which device we query...
  auto *fb = static_cast<const Photon*>(owlBufferGetPointer(program.photonsBuffer, 0));
  auto count = *(int*)owlBufferGetPointer(program.photonsCount, 0);

  writeAlivePhotons(fb, count, "photons.txt");

  LOG("destroying devicegroup ...");
  owlContextDestroy(program.owlContext);

  LOG_OK("seems all went OK; app is done, this should be the last output ...");
  return 0;
}
