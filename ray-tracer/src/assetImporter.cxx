#include "assetImporter.h"

#include <queue>

#include "../../externals/assimp/include/assimp/scene.h"
#include "../../externals/assimp/include/assimp/postprocess.h"

std::vector<Mesh>& AssetImporter::get_geometry() {
    if (this->meshes.empty()) { // lazily initialise meshes
        this->initialise_meshes();
    }

    return meshes;
}

void AssetImporter::initialise_meshes() {
    const aiScene *scene = importer->ReadFile(this->path,
            aiProcess_Triangulate      |
            aiProcess_JoinIdenticalVertices  |
            aiProcess_SortByPType);

    std::queue<aiNode*> unprocessed_nodes;
    unprocessed_nodes.push(scene->mRootNode);

    while (!unprocessed_nodes.empty()) { // for each node in the hierarchy
        auto current_node = unprocessed_nodes.front();
        unprocessed_nodes.pop();

        // Add node's children to unprocessed_nodes
        for (int i = 0; i < current_node->mNumChildren; i++) {
            unprocessed_nodes.push(current_node->mChildren[i]);
        }

        for (int i = 0; i < current_node->mNumMeshes; i++) { // for each mesh in the node
            auto current_mesh = scene->mMeshes[current_node->mMeshes[i]];
            std::vector<owl::vec3f> verts;
            int vert_count = 0;
            std::vector<owl::vec3i> idx;
            // TODO: Colour

            // FIXME: As it stands, this should work, but there are duplicate verts in the output vector.
            for (int j = 0; j < current_mesh->mNumFaces; j++) { // for each face in the mesh
                auto current_face = current_mesh->mFaces[j];
                std::vector<int> face_indices;

                for (int k = 0; k < current_face.mNumIndices; k++) { // for each index (vertex) in the face
                    verts.push_back(owl::vec3f(
                        current_mesh->mVertices[current_face.mIndices[k]].x,
                        current_mesh->mVertices[current_face.mIndices[k]].y,
                        current_mesh->mVertices[current_face.mIndices[k]].z
                    ));
                    face_indices.push_back(++vert_count);
                }
                // if current_face.mNumIndices != 3, we're in deep shit.
                assert(face_indices.size() == 3);
                idx.push_back(owl::vec3i(
                    face_indices.at(0),
                    face_indices.at(1),
                    face_indices.at(2)
                ));
            }
            Mesh output_mesh;
            output_mesh.vertices = verts;
            output_mesh.indices = idx;

            this->meshes.push_back(output_mesh);
        }
    }
}