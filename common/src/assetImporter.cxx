#include "assetImporter.h"

#include <fstream>
#include <map>
#include <queue>
#include <set>

#include "mesh.h"
#include "../../externals/assimp/include/assimp/scene.h"
#include "../../externals/assimp/include/assimp/postprocess.h"

static std::vector<Mesh> extract_objects(const aiScene*);
static void assign_materials(std::vector<Mesh>&,const std::string&);
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
  assign_materials(world->meshes, path);

  return world;
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

      aiString name;
      const auto material_idx = current_mesh->mMaterialIndex;
      scene->mMaterials[material_idx]->Get(AI_MATKEY_NAME,name);
      output_mesh.name = name.C_Str();

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
    // Skip empty lines and comments
    if (line.empty() || line[0] == '#') {
      continue;
    }

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

using MaterialProperties = std::tuple<owl::vec3f, float, float, float, float>;
using MaterialMap = std::map<std::string, MaterialProperties>;

static MaterialMap readMaterialFile(const std::string& path) {
  const std::size_t last_dot = path.find_last_of('.');
  const auto base_path = path.substr(0,last_dot);

  std::string filename = base_path + ".mtl";
  std::replace(filename.begin(), filename.end(), '/', '\\');

  MaterialMap materials_map;
  std::ifstream file(filename);

  if (!file.is_open()) {
    std::cerr << "Error: Unable to open file " << filename << std::endl;
    return materials_map;
  }

  std::string line;
  while (std::getline(file, line)) {
    // Skip empty lines and comments
    if (line.empty() || line[0] == '#') {
      continue;
    }

    std::istringstream iss(line);
    std::string name;
    float albedo_r, albedo_g, albedo_b, diffuse, specular, transmission, refraction_idx;

    if (iss >> name >> albedo_r >> albedo_g >> albedo_b >> diffuse >> specular >> transmission >> refraction_idx) {
      auto albedo = owl::vec3f(albedo_r, albedo_g, albedo_b);
      materials_map[name] = std::make_tuple(albedo, diffuse, specular, transmission, refraction_idx);
    } else {
      std::cerr << "Warning: Invalid line format: " << line << std::endl;
    }
  }

  file.close();
  return materials_map;
}

static void assign_materials(std::vector<Mesh>& meshes, const std::string& path) {
  using namespace owl;

  const MaterialMap mat_map = readMaterialFile(path);

  Material default_material;
  default_material.albedo = vec3f(1.,1.,1.);
  default_material.diffuse = 1.f;
  default_material.specular = 0.f;
  default_material.transmission = 0.f;
  default_material.refraction_idx = 0.f;

  /* Unsure if structured bindings are a good idea here */
  for (auto & [name, _v, _i, material]: meshes) {
    if (mat_map.count(name) == 0) {
      material = std::make_shared<Material>(default_material);
      continue;
    }
    auto current_mat = mat_map.at(name);
    Material mesh_mat;
    mesh_mat.albedo = std::get<0>(current_mat);
    mesh_mat.diffuse = std::get<1>(current_mat);
    mesh_mat.specular = std::get<2>(current_mat);
    mesh_mat.transmission = std::get<3>(current_mat);
    mesh_mat.refraction_idx = std::get<4>(current_mat);
    material = std::make_shared<Material>(mesh_mat);
  }
}