#pragma once

#include "owl/common/math/vec.h"

struct Photon
{
    owl::vec3f pos;
    owl::vec3f dir;
    int power;
    owl::vec3f color;
};