#pragma once

#include <iostream>
#include "toml.hpp"

inline toml::value parse_config(const std::string& path) {
    toml::value tbl;
    try {
        tbl = toml::parse(path);
        std::cout << "Loaded config:\n" << tbl << '\n';
    }
    catch (const toml::syntax_error & err) {
        std::cerr << "Parsing failed:\n" << err.what() << "\n";
    }

    return tbl;
}

inline owl::vec2i toml_to_vec2i(toml::value cfg, const std::string& key) {
    auto arr = toml::find<std::array<int, 2>>(cfg, key);
    return { arr[0], arr[1] };
}

inline owl::vec3f toml_to_vec3f(toml::value cfg, const std::string& key) {
    auto arr = toml::find<std::array<float, 3>>(cfg, key);
    return { arr[0], arr[1],arr[2] };
}