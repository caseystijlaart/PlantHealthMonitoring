#pragma once

#include "PlantTypes.hpp"

namespace pof02 {

class Stress {
public:
    static float Score(Level level);
    static float Combined(Level moisture, Level temp, Level humidity, Level light);
};

} // namespace pof02
