#include "../include/program.h"
#include <vector>
#include "owl/owl.h"
#include "../../externals/stb/stb_image_write.h"
#include "../include/deviceCode.h"
#include "../include/photonViewer.h"

constexpr owl3f sky_color = owl3f { 255./255., 255./255., 255./255. };

void PhotonViewer::setupMissProgram() {
  owlMissProgCreate(owlContext,owlModule,"photonViewerMiss",0, nullptr,-1);
}

void PhotonViewer::setupClosestHitProgram() {
  owlGeomTypeSetClosestHit(trianglesGeomType,0,owlModule,"photonViewerClosestHit");
}

void PhotonViewer::setupRaygenProgram() {
  OWLVarDecl rayGenVars[] = {
  { "frameBuffer",OWL_BUFPTR,OWL_OFFSETOF(PhotonViewerRGD,frameBuffer)},
  { "frameBufferSize",OWL_INT2,OWL_OFFSETOF(PhotonViewerRGD,frameBufferSize)},
  { "world",OWL_GROUP,OWL_OFFSETOF(PhotonViewerRGD,world)},
  { "camera.pos",OWL_FLOAT3,OWL_OFFSETOF(PhotonViewerRGD,camera.pos)},
  { "camera.dir_00",OWL_FLOAT3,OWL_OFFSETOF(PhotonViewerRGD,camera.dir_00)},
  { "camera.dir_du",OWL_FLOAT3,OWL_OFFSETOF(PhotonViewerRGD,camera.dir_du)},
  { "camera.dir_dv",OWL_FLOAT3,OWL_OFFSETOF(PhotonViewerRGD,camera.dir_dv)},
  { "photons",OWL_BUFPTR,OWL_OFFSETOF(PhotonViewerRGD,photons)},
  { "numPhotons",OWL_INT,OWL_OFFSETOF(PhotonViewerRGD,numPhotons)},
  { /* sentinel to mark end of list */ }
  };

  rayGen = owlRayGenCreate(owlContext,owlModule,"photonViewerRayGen",
                           sizeof(PhotonViewerRGD),
                           rayGenVars,-1);

  // ----------- set variables  ----------------------------
  owlRayGenSetBuffer(rayGen,"frameBuffer",frameBuffer);
  owlRayGenSet2i(rayGen,"frameBufferSize",reinterpret_cast<const owl2i&>(frameBufferSize));
  owlRayGenSetGroup(rayGen,"world",worldGroup);
  owlRayGenSet3f(rayGen,"camera.pos",reinterpret_cast<const owl3f&>(camera.pos));
  owlRayGenSet3f(rayGen,"camera.dir_00",reinterpret_cast<const owl3f&>(camera.dir_00));
  owlRayGenSet3f(rayGen,"camera.dir_du",reinterpret_cast<const owl3f&>(camera.dir_du));
  owlRayGenSet3f(rayGen,"camera.dir_dv",reinterpret_cast<const owl3f&>(camera.dir_dv));
  owlRayGenSetBuffer(rayGen,"photons",photonsBuffer);
  owlRayGenSet1i(rayGen,"numPhotons",numPhotons);
}
