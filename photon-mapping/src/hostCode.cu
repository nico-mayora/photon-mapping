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
#include "../../common/src/configLoader.h"

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
          { "maxPhotons",OWL_INT,OWL_OFFSETOF(PointLightRGD,maxPhotons)},
          { "maxBounces",OWL_INT,OWL_OFFSETOF(PointLightRGD, maxDepth)},
          {"causticsMode", OWL_BOOL, OWL_OFFSETOF(PointLightRGD, causticsMode)},
          { "world",OWL_GROUP,OWL_OFFSETOF(PointLightRGD,world)},
          { "position",OWL_FLOAT3,OWL_OFFSETOF(PointLightRGD,position)},
          { "color",OWL_FLOAT3,OWL_OFFSETOF(PointLightRGD,color)},
          { "intensity",OWL_FLOAT,OWL_OFFSETOF(PointLightRGD,intensity)},
          { /* sentinel to mark end of list */ }
  };

  program.rayGen = owlRayGenCreate(program.owlContext,program.owlModule,"pointLightRayGen",
                                   sizeof(PointLightRGD),
                                   rayGenVars,-1);

  owlRayGenSetGroup(program.rayGen,"world",program.geometryData.worldGroup);
  owlRayGenSet1i(program.rayGen,"maxBounces",program.maxDepth);
}

void runPointLightRayGen(Program &program, const LightSource &light, bool causticsMode) {
  owlRayGenSet1b(program.rayGen,"causticsMode",causticsMode);
  owlRayGenSet3f(program.rayGen,"position",reinterpret_cast<const owl3f&>(light.pos));
  owlRayGenSet3f(program.rayGen,"color",reinterpret_cast<const owl3f&>(light.rgb));
  owlRayGenSet1f(program.rayGen,"intensity",light.power);

  if (causticsMode) {
    owlRayGenSetBuffer(program.rayGen,"photons",program.causticsPhotonsBuffer);
    owlRayGenSetBuffer(program.rayGen,"photonsCount",program.causticsPhotonsCount);
    owlRayGenSet1i(program.rayGen,"maxPhotons",program.maxCausticsPhotons);
  } else {
    owlRayGenSetBuffer(program.rayGen,"photons",program.photonsBuffer);
    owlRayGenSetBuffer(program.rayGen,"photonsCount",program.photonsCount);
    owlRayGenSet1i(program.rayGen,"maxPhotons",program.maxPhotons);
  }

  const int initialPhotons = (int)(light.power * program.photonsPerWatt);

  owlBuildSBT(program.owlContext);
  owlRayGenLaunch2D(program.rayGen,initialPhotons,1);
}

void initPhotonBuffers(Program &program) {
  program.photonsBuffer = owlHostPinnedBufferCreate(program.owlContext, OWL_USER_TYPE(Photon), program.maxPhotons);
  program.photonsCount = owlHostPinnedBufferCreate(program.owlContext, OWL_INT, 1);
  owlBufferClear(program.photonsCount);

  program.causticsPhotonsBuffer = owlHostPinnedBufferCreate(program.owlContext,OWL_USER_TYPE(Photon),program.maxCausticsPhotons);
  program.causticsPhotonsCount = owlHostPinnedBufferCreate(program.owlContext, OWL_INT, 1);
  owlBufferClear(program.causticsPhotonsCount);
}

void runNormal(Program &program, const std::string &output_filename) {
  for (auto light : program.world->light_sources) {
    runPointLightRayGen(program, light, false);
  }

  LOG("done with launch, writing photons ...")
  auto *fb = static_cast<const Photon*>(owlBufferGetPointer(program.photonsBuffer, 0));
  auto count = *(int*)owlBufferGetPointer(program.photonsCount, 0);

  writeAlivePhotons(fb, count, output_filename);
}

void runCaustics(Program &program, const std::string &output_filename) {
  for (auto light : program.world->light_sources) {
    runPointLightRayGen(program, light, true);
  }

  LOG("done with launch, writing caustics photons ...")
  auto *fb = static_cast<const Photon*>(owlBufferGetPointer(program.causticsPhotonsBuffer, 0));
  auto count = *(int*)owlBufferGetPointer(program.causticsPhotonsCount, 0);

  writeAlivePhotons(fb, count, output_filename);
}

int main(int ac, char **av)
{
  LOG("Starting up...");

  Program program;
  program.owlContext = owlContextCreate(nullptr,1);
  program.owlModule = owlModuleCreate(program.owlContext, deviceCode_ptx);
  owlContextSetRayTypeCount(program.owlContext, 1);

  LOG("Loading Config file...")

  auto cfg = parse_config();

  auto photons_filename = cfg["data"]["photons_file"].as_string();
  auto caustics_photons_filename = cfg["data"]["caustics_photons_file"].as_string();
  auto model_path = cfg["data"]["model_path"].as_string();
  program.maxPhotons = cfg["photon-mapper"]["max_photons"].as_integer();
  program.maxCausticsPhotons = cfg["photon-mapper"]["max_caustics_photons"].as_integer();
  program.maxDepth = cfg["photon-mapper"]["max_depth"].as_integer();
  program.photonsPerWatt = cfg["photon-mapper"]["photons_per_watt"].as_integer();


  auto *ai_importer = new Assimp::Importer;
  program.world =  assets::import_scene(ai_importer, model_path);

  LOG_OK("Loaded world.")

  program.geometryData = loadGeometry(program.owlContext, program.world);

  owlGeomTypeSetClosestHit(program.geometryData.trianglesGeomType, 0, program.owlModule,"triangleMeshClosestHit");
  owlMissProgCreate(program.owlContext, program.owlModule, "miss", 0, nullptr, -1);

  initPhotonBuffers(program);

  setupPointLightRayGenProgram(program);

  owlBuildPrograms(program.owlContext);
  owlBuildPipeline(program.owlContext);

  LOG("launching ...")

  runNormal(program, photons_filename);
  runCaustics(program, caustics_photons_filename);

  LOG("destroying devicegroup ...");
  owlContextDestroy(program.owlContext);

  LOG_OK("seems all went OK; app is done, this should be the last output ...");
  return 0;
}
