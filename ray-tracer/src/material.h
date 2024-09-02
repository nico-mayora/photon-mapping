#pragma once
#include "owl/common/math/vec.h"

class Material {
  public:
    virtual ~Material() = default;
    // TODO: create real function signature.
    virtual bool scatter() = 0;
};

struct Lambertian final : Material {
    explicit Lambertian(const owl::vec3f& albedo): albedo(albedo) {}
    owl::vec3f albedo;
    bool scatter() override { return false; }
};

struct Specular : Material {
    double roughness;
};

struct Glass : Material {
    double refraction_idx;
};