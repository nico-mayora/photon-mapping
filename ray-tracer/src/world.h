#pragma once
#include <vector>

#include "owl/common/math/vec.h"
#include "mesh.h"

enum LightType {
    POINT_LIGHT,
    SQUARE_LIGHT,
};

struct LightSource {
    LightType source_type;
    owl::vec3f pos;
    double power;
    /* for emission surface */
    owl::vec3f normal;
    double side_length;
};

struct Camera {
    owl::vec3f origin;
    owl::vec3f lower_left_corner;
    owl::vec3f horizontal;
    owl::vec3f vertical;
};

struct World {
    std::vector<LightSource> light_sources;
    std::vector<Mesh> meshes;
    Camera camera;
};