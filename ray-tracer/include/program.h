#pragma once

#include "owl/owl.h"
#include "../../common/src/camera.h"
#include "photon.h"
#include "../../common/src/world.h"
#include "owl/common/math/vec.h"

class Program {
public:
    OWLContext owlContext;
    OWLModule owlModule;
    OWLRayGen rayGen;

    OWLBuffer frameBuffer;
    owl::vec2i frameBufferSize;

    OWLGeomType trianglesGeomType;
    OWLGroup trianglesGroup;
    OWLGroup worldGroup;

    OWLBuffer photonsBuffer;
    int numPhotons;
    OWLBuffer lightsBuffer;
    int numLights;

    Camera camera;
    std::vector<OWLGeom> geometry;

    Program(const char *ptx, const owl::vec2i &frameBufferSize);

    void loadPhotons(const std::string& filename);
    void loadGeometry(const std::unique_ptr<World> &world);
    void loadLights(const std::unique_ptr<World> &world);
    void setupCamera(owl::vec3f lookFrom, owl::vec3f lookAt, owl::vec3f lookUp, float aspect, float fovy);
    void build();
    void run();
    void destroy();

    virtual void setupRaygenProgram() = 0;
    virtual void setupMissProgram() = 0;
    virtual void setupClosestHitProgram() = 0;
};

class Raytracer : public Program {
public:
    Raytracer(const char *ptx, const owl::vec2i &frameBufferSize) : Program(ptx, frameBufferSize) {}

    void setupRaygenProgram() override;
    void setupMissProgram() override;
    void setupClosestHitProgram() override;
};

class PhotonViewer : public Program {
public:
    PhotonViewer(const char *ptx, const owl::vec2i &frameBufferSize) : Program(ptx, frameBufferSize) {}

    void setupRaygenProgram() override;
    void setupMissProgram() override;
    void setupClosestHitProgram() override;
};