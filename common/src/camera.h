#pragma once

#include <owl/common/math/vec.h>

struct Camera {
    owl::vec3f pos;
    owl::vec3f dir_00; // out-of-screen
    owl::vec3f dir_du; // left-to-right
    owl::vec3f dir_dv; // bottom-to-top
};