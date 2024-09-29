#pragma once

#include <cukd/knn.h>
#define K_NEAREST_NEIGHBOURS 4
#define K_MAX_DISTANCE 50

inline __device__
cukd::FixedCandidateList<K_NEAREST_NEIGHBOURS> KNearestPhotons(
    const owl::vec3f& queryPoint,
    const Photon* photons,
    const int numPoints
) {
    cukd::FixedCandidateList<K_NEAREST_NEIGHBOURS> closest(K_MAX_DISTANCE);
    auto sqrDistOfFurthestOneInClosest = cukd::stackBased::knn<cukd::FixedCandidateList<K_NEAREST_NEIGHBOURS>,Photon, Photon_traits>(
        closest,queryPoint,photons,numPoints
    );
    return closest;
}