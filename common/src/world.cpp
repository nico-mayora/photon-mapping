#include "world.h"

GeometryData loadGeometry(OWLContext &owlContext, const std::unique_ptr<World> &world){
  GeometryData data;

  OWLVarDecl trianglesGeomVars[] = {
          { "index",  OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,index)},
          { "vertex", OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,vertex)},
          { "material", OWL_BUFPTR, OWL_OFFSETOF(TrianglesGeomData,material)},
          { nullptr /* Sentinel to mark end-of-list */}
  };

  data.trianglesGeomType = owlGeomTypeCreate(owlContext,
                                                OWL_TRIANGLES,
                                                sizeof(TrianglesGeomData),
                                                trianglesGeomVars,-1);

  const int numMeshes = static_cast<int>(world->meshes.size());

  for (int meshID=0; meshID<numMeshes; meshID++) {
    auto mesh = world->meshes[meshID];
    auto vertices = mesh.vertices;
    auto indices = mesh.indices;
    auto material = mesh.material;

    std::vector<Material> mats_vec = { *material };

    OWLBuffer vertexBuffer
            = owlDeviceBufferCreate(owlContext,OWL_FLOAT3,vertices.size(), vertices.data());
    OWLBuffer indexBuffer
            = owlDeviceBufferCreate(owlContext,OWL_INT3,indices.size(), indices.data());
    OWLBuffer materialBuffer
            = owlDeviceBufferCreate(owlContext,OWL_USER_TYPE(Material),1, mats_vec.data());

    OWLGeom trianglesGeom
            = owlGeomCreate(owlContext,data.trianglesGeomType);

    owlTrianglesSetVertices(trianglesGeom,vertexBuffer,
                            vertices.size(),sizeof(owl::vec3f),0);
    owlTrianglesSetIndices(trianglesGeom,indexBuffer,
                           indices.size(),sizeof(owl::vec3i),0);

    owlGeomSetBuffer(trianglesGeom,"vertex",vertexBuffer);
    owlGeomSetBuffer(trianglesGeom,"index",indexBuffer);
    owlGeomSetBuffer(trianglesGeom,"material", materialBuffer);

    data.geometry.push_back(trianglesGeom);
  }

  data.trianglesGroup = owlTrianglesGeomGroupCreate(owlContext,data.geometry.size(),data.geometry.data());
  owlGroupBuildAccel(data.trianglesGroup);

  data.worldGroup = owlInstanceGroupCreate(owlContext,1);
  owlInstanceGroupSetChild(data.worldGroup,0,data.trianglesGroup);
  owlGroupBuildAccel(data.worldGroup);

  return data;
}