#pragma once

#include "owl/owl.h"
#include "../../common/src/camera.h"

struct Context {
  OWLContext owlContext;
  OWLModule owlModule;
  OWLBuffer frameBuffer;
  OWLGroup trianglesGroup;
  OWLGroup worldGroup;
  Camera camera;
};