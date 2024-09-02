#pragma once

#include <vector>

#include "../../externals/assimp/include/assimp/Importer.hpp"
#include "owl/common/math/vec.h"

/* This class stores the mesh in the format expected by Optix.
 * TODO:
 *  Textures
 *  Different materials (only Lambertian rn)
 */

/* The vectors need to be (trivially) transformed into regular arrays
   before being passed into OptiX */
struct Mesh {
    std::vector<owl::vec3f> vertices;
    std::vector<owl::vec3i> indices;
    std::vector<owl::vec3f> colours;
};

class AssetImporter {
private:
    std::unique_ptr<Assimp::Importer> importer;

    const std::string path;
    std::vector<Mesh> meshes;

    void initialise_meshes();

public:
    AssetImporter(Assimp::Importer *importer, std::string path): path(path), importer(importer) {};
    std::vector<Mesh>& get_geometry();
};
