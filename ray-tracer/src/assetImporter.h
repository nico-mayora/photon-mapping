#pragma once

#include <utility>
#include <vector>

#include "mesh.h"
#include "world.h"
#include "../../externals/assimp/include/assimp/Importer.hpp"
#include "owl/common/math/vec.h"

/*
 * TODO: Image textures
 */

class AssetImporter {
    std::unique_ptr<Assimp::Importer> importer;

    const std::string path;
    std::vector<Mesh> meshes;

    void initialise_meshes();

public:
    AssetImporter(Assimp::Importer *importer, std::string path): importer(importer), path(std::move(path)) {};
    std::vector<Mesh>& get_geometry();
};
