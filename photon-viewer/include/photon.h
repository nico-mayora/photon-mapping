#pragma once

#include "owl/common/math/vec.h"

struct Photon {
    // Data for the photon
    owl::vec3f pos;
    owl::vec3f dir;
    owl::vec3f color;
    owl::vec2i pixel;
};