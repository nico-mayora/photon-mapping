#pragma once
#include "owl/common/math/vec.h"
#include "../cuda/deviceCode.h"


/* The vectors need to be (trivially) transformed into regular arrays
   before being passed into OptiX */
struct Mesh {
    std::vector<owl::vec3f> vertices;
    std::vector<owl::vec3i> indices;
    std::shared_ptr<Material> material;
};