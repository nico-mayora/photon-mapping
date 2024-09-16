#include "assetImporter.h"

#include <fstream>
#include <queue>
#include <set>

#include "../../externals/assimp/include/assimp/scene.h"
#include "../../externals/assimp/include/assimp/postprocess.h"

static std::vector<Mesh> extract_objects(const aiScene*);
static std::vector<LightSource> extract_lights(std::string&);

std::unique_ptr<World> assets::import_scene(Assimp::Importer* importer, std::string& path) {
    std::unique_ptr<World> world(new World);
    const aiScene *scene = importer->ReadFile(path,
            aiProcess_Triangulate
            | aiProcess_JoinIdenticalVertices
            | aiProcess_SortByPType);

    assert(scene != nullptr);
    world->meshes = extract_objects(scene);
    world->light_sources = extract_lights(path);

    return world;
}

static std::shared_ptr<Material> mesh_material(const aiScene *scene, const aiMesh *mesh) {
    const auto material_idx = mesh->mMaterialIndex;
    const auto material = scene->mMaterials[material_idx];

    // TODO: Non-lambertian
    auto type = LAMBERTIAN;
    aiColor3D colour;
    material->Get(AI_MATKEY_COLOR_DIFFUSE, colour);

    auto mat = std::make_shared<Material>();
    mat->albedo = owl::vec3f(colour.r, colour.g, colour.b);
    mat->surface_type = type;
    mat->specular_roughness = -1;
    mat->refraction_idx = -1;

    return mat;
}

static std::vector<Mesh> extract_objects(const aiScene *scene) {
    std::queue<std::pair<aiNode*, aiMatrix4x4>> unprocessed_nodes;
    unprocessed_nodes.emplace(scene->mRootNode, aiMatrix4x4());

    std::vector<Mesh> meshes;

    while (!unprocessed_nodes.empty()) { // for each node in the hierarchy
        const auto [current_node, curr_transform] = unprocessed_nodes.front();
        unprocessed_nodes.pop();

        auto transform = current_node->mTransformation * curr_transform;

        // Add node's children to unprocessed_nodes
        for (int i = 0; i < current_node->mNumChildren; i++) {
            unprocessed_nodes.emplace(current_node->mChildren[i], transform);
        }

        for (int i = 0; i < current_node->mNumMeshes; i++) { // for each mesh in the node
            const auto current_mesh = scene->mMeshes[current_node->mMeshes[i]];
            std::vector<owl::vec3f> verts;
            int vert_count = 0;
            std::vector<owl::vec3i> idx;

            for (int j = 0; j < current_mesh->mNumFaces; j++) { // for each face in the mesh
                const auto current_face = current_mesh->mFaces[j];
                std::vector<int> face_indices;

                for (int k = 0; k < current_face.mNumIndices; k++) { // for each index (vertex) in the face
                    const auto current_vert = current_mesh->mVertices[current_face.mIndices[k]];
                    auto transformed_vertex = transform * current_vert;
                    auto vertex_pos = owl::vec3f(transformed_vertex.x, transformed_vertex.y, transformed_vertex.z);

                    auto vertex_position_in_verts = std::find(verts.begin(), verts.end(), vertex_pos);
                    if (vertex_position_in_verts == std::end(verts)) { // vertex is not already in `verts` collection.
                        verts.emplace_back(vertex_pos);
                        face_indices.push_back(vert_count++);
                        continue;
                    }
                    const auto numeric_position = distance(verts.begin(), vertex_position_in_verts); // NOLINT(*-narrowing-conversions)

                    face_indices.push_back(numeric_position); // NOLINT(*-narrowing-conversions)
                }
                // if current_face.mNumIndices != 3, we're in deep shit.
                assert(face_indices.size() == 3);
                idx.emplace_back(
                    face_indices.at(0),
                    face_indices.at(1),
                    face_indices.at(2)
                );
            }
            Mesh output_mesh;
            output_mesh.vertices = verts;
            output_mesh.indices = idx;
            output_mesh.material = mesh_material(scene, current_mesh);

            meshes.push_back(output_mesh);
        }
    }
    return meshes;
}


static std::vector<LightSource> extract_lights(std::string& path) {
    const std::size_t last_slash = path.find_last_of("/\\");
    const auto base_path = path.substr(0,last_slash);

    auto full_path = base_path + "/lights.txt";
    std::replace(full_path.begin(), full_path.end(), '/', '\\');

    std::vector<LightSource> lightSources;
    std::ifstream file(full_path);

    if (!file.is_open()) {
        throw std::runtime_error("Unable to open file: " + full_path);
    }

    std::string line;
    while (std::getline(file, line)) {
        std::istringstream iss(line);
        LightSource light;

        light.source_type = POINT_LIGHT;  // Assuming all lights are point lights

        if (!(iss >> light.pos.x >> light.pos.y >> light.pos.z >>
              light.rgb.x >> light.rgb.y >> light.rgb.z >>
              light.power)) {
            throw std::runtime_error("Invalid light source data format");
              }

        lightSources.push_back(light);
    }

    return lightSources;
}
