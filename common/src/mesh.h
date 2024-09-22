#pragma once

#include <vector>
#include "owl/common/math/vec.h"
#include "material.h"

/* variables for the triangle mesh geometry */
struct TrianglesGeomData
{
    /*! material we use for the entire mesh */
    Material *material;
    /*! array/buffer of vertex indices */
    owl::vec3i *index;
    /*! array/buffer of vertex positions */
    owl::vec3f *vertex;
};

/* The vectors need to be (trivially) transformed into regular arrays
   before being passed into OptiX */
struct Mesh {
    std::vector<owl::vec3f> vertices;
    std::vector<owl::vec3i> indices;
    std::shared_ptr<Material> material;
};