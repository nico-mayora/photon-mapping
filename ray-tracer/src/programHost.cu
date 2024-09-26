#include "../include/program.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include "owl/owl.h"
#include "../../externals/stb/stb_image_write.h"
#include "../../common/src/common.h"
#include <cukd/builder.h>

Program::Program(const char *ptx, const owl::vec2i &frameBufferSize) {
  owlContext = owlContextCreate(nullptr,1);
  owlModule = owlModuleCreate(owlContext, ptx);
  owlContextSetRayTypeCount(owlContext, 2);

  this->frameBufferSize = frameBufferSize;
  frameBuffer = owlHostPinnedBufferCreate(owlContext,OWL_INT,frameBufferSize.x * frameBufferSize.y);
}

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

void Program::loadPhotons(const std::string& filename) {
  auto photonsFromFile = readPhotonsFromFile(filename, numPhotons);
  photonsBuffer = owlDeviceBufferCreate(owlContext, OWL_USER_TYPE(Photon), numPhotons, photonsFromFile);

  Photon* photons;
  CUKD_CUDA_CALL(MallocManaged((void **) &photons, numPhotons * sizeof(Photon)));
  for (int i=0; i < numPhotons; i++) {
    photons[i].pos = photonsFromFile[i].pos;
    photons[i].dir = photonsFromFile[i].dir;
    photons[i].color = photonsFromFile[i].color;
  }
  cukd::buildTree<Photon,Photon_traits>(photons,numPhotons);
}

void Program::loadGeometry(const std::unique_ptr<World> &world){
  OWLVarDecl trianglesGeomVars[] = {
          { "index",  OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,index)},
          { "vertex", OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,vertex)},
          { "material", OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,material)},
          { nullptr /* Sentinel to mark end-of-list */}
  };

  trianglesGeomType = owlGeomTypeCreate(owlContext,
                                        OWL_TRIANGLES,
                                        sizeof(TrianglesGeomData),
                                        trianglesGeomVars,-1);

  LOG("building geometries ...");

  const int numMeshes = static_cast<int>(world->meshes.size());

  for (int meshID=0; meshID<numMeshes; meshID++) {
    auto mesh = world->meshes[meshID];
    auto vertices = mesh.vertices;
    auto indices = mesh.indices;
    auto material = mesh.material;

    std::vector<Material> mats_vec = { *material };

    OWLBuffer vertexBuffer
            = owlDeviceBufferCreate(owlContext,OWL_FLOAT3,vertices.size(), vertices.data());
    OWLBuffer indexBuffer
            = owlDeviceBufferCreate(owlContext,OWL_INT3,indices.size(), indices.data());
    OWLBuffer materialBuffer
            = owlDeviceBufferCreate(owlContext,OWL_USER_TYPE(Material),1, mats_vec.data());

    OWLGeom trianglesGeom
            = owlGeomCreate(owlContext,trianglesGeomType);

    owlTrianglesSetVertices(trianglesGeom,vertexBuffer,
                            vertices.size(),sizeof(owl::vec3f),0);
    owlTrianglesSetIndices(trianglesGeom,indexBuffer,
                           indices.size(),sizeof(owl::vec3i),0);

    owlGeomSetBuffer(trianglesGeom,"vertex",vertexBuffer);
    owlGeomSetBuffer(trianglesGeom,"index",indexBuffer);
    owlGeomSetBuffer(trianglesGeom,"material", materialBuffer);

    geometry.push_back(trianglesGeom);
  }

  trianglesGroup = owlTrianglesGeomGroupCreate(owlContext,geometry.size(),geometry.data());
  owlGroupBuildAccel(trianglesGroup);

  worldGroup = owlInstanceGroupCreate(owlContext,1);
  owlInstanceGroupSetChild(worldGroup,0,trianglesGroup);
  owlGroupBuildAccel(worldGroup);
}

void Program::setupCamera(owl::vec3f lookFrom, owl::vec3f lookAt, owl::vec3f lookUp, float aspect, float fovy) {
  camera.pos = lookFrom;
  camera.dir_00 = normalize(lookAt-lookFrom);
  camera.dir_du = fovy * aspect * normalize(cross(camera.dir_00, lookUp));
  camera.dir_dv = fovy * normalize(cross(camera.dir_du, camera.dir_00));
  camera.dir_00 -= 0.5f * (camera.dir_du + camera.dir_dv);
}

void Program::loadLights(const std::unique_ptr<World> &world) {
  numLights = static_cast<int>(world->light_sources.size());
  lightsBuffer =  owlDeviceBufferCreate(owlContext, OWL_USER_TYPE(LightSource),world->light_sources.size(), world->light_sources.data());
}

void Program::build() {
  owlBuildPrograms(owlContext);
  owlBuildPipeline(owlContext);
  owlBuildSBT(owlContext);
}

void Program::run() {
  owlRayGenLaunch2D(rayGen, frameBufferSize.x, frameBufferSize.y);
}

void Program::destroy() {
  owlContextDestroy(owlContext);
}
