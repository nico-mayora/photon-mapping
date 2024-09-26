#include "../include/program.h"
#include <vector>
#include "owl/owl.h"
#include "../../externals/stb/stb_image_write.h"
#include "../include/deviceCode.h"

constexpr owl3f sky_color = owl3f { 255./255., 255./255., 255./255. };

void Raytracer::setupMissProgram() {
  OWLVarDecl missProgVars[] = {
    { "sky_color", OWL_FLOAT3, OWL_OFFSETOF(MissProgData, sky_color)},
    { /* sentinel to mark end of list */ }
  };

  auto missProg = owlMissProgCreate(owlContext,owlModule,"miss",sizeof(MissProgData),missProgVars,-1);
  auto shadowMissProg = owlMissProgCreate(owlContext,owlModule,"shadow",0,nullptr,-1);

  owlMissProgSet3f(missProg,"sky_color", sky_color);
}

void Raytracer::setupClosestHitProgram() {
  owlGeomTypeSetClosestHit(trianglesGeomType,0,owlModule,"TriangleMesh");
  owlGeomTypeSetClosestHit(trianglesGeomType,1,owlModule,"shadow");
}

void Raytracer::setupRaygenProgram(){
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

  rayGen = owlRayGenCreate(owlContext,owlModule,"simpleRayGen",
                            sizeof(RayGenData),
                            rayGenVars,-1);

  // ----------- set variables  ----------------------------
  owlRayGenSetBuffer(rayGen,"fbPtr",        frameBuffer);
  owlRayGenSet2i    (rayGen,"fbSize",       reinterpret_cast<const owl2i&>(frameBufferSize));
  owlRayGenSetGroup (rayGen,"world",        worldGroup);
  owlRayGenSet3f    (rayGen,"camera.pos",   reinterpret_cast<const owl3f&>(camera.pos));
  owlRayGenSet3f    (rayGen,"camera.dir_00",reinterpret_cast<const owl3f&>(camera.dir_00));
  owlRayGenSet3f    (rayGen,"camera.dir_du",reinterpret_cast<const owl3f&>(camera.dir_du));
  owlRayGenSet3f    (rayGen,"camera.dir_dv",reinterpret_cast<const owl3f&>(camera.dir_dv));
  owlRayGenSet3f    (rayGen,"sky_color",    sky_color);
  owlRayGenSetBuffer(rayGen,"lights",       lightsBuffer);
  owlRayGenSet1i    (rayGen,"numLights",    numLights);
  owlRayGenSetBuffer(rayGen,"photons",      photonsBuffer);
  owlRayGenSet1i    (rayGen,"numPhotons",   numPhotons);
}
