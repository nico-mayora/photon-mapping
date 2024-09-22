#pragma once

#include <utility>
#include <vector>

#include "mesh.h"
#include "world.h"
#include "assimp/Importer.hpp"
#include "owl/common/math/vec.h"

/*
 * TODO:
 *  Image textures
 *  Import camera
 *  Import light sources
 */

namespace assets {
    std::unique_ptr<World> import_scene(Assimp::Importer* importer, std::string& path);
};
