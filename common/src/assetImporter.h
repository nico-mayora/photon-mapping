#pragma once

#include "world.h"
#include "assimp/Importer.hpp"
#include "owl/common/math/vec.h"

namespace assets {
    std::unique_ptr<World> import_scene(Assimp::Importer* importer, std::string& path);
};
