#pragma once

#include <iostream>
#include "toml.hpp"

#define CONFIG_PATH "../config.toml"

inline toml::value parse_config() {
    toml::value tbl;
    try {
        tbl = toml::parse(CONFIG_PATH);
        std::cout << "Loaded config:\n" << tbl << '\n';
    }
    catch (const toml::syntax_error & err) {
        std::cerr << "Parsing failed:\n" << err.what() << "\n";
    }

    return tbl;
}

inline owl::vec2i toml_to_vec2i(const toml::value &cfg) {
  const auto& arr = cfg.as_array();
  return { (int)arr[0].as_integer(), (int)arr[1].as_integer() };
}

inline owl::vec3f toml_to_vec3f(const toml::value &cfg) {
    const auto& arr = cfg.as_array();
    return { (float)arr[0].as_floating(), (float)arr[1].as_floating(),(float)arr[2].as_floating() };
}