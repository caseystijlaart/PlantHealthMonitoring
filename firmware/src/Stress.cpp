#include "Stress.hpp"

namespace pof02 {

float Stress::Score(Level level) {
    switch (level) {
        case Level::kOk:
            return 0.0f;
        case Level::kLow :
        case Level::kHigh:
            return 1.0f;
    }
    return 1.0f;
}

float Stress::Combined(Level moisture, Level temp, Level humidity, Level light) {
    return (Score(moisture) + Score(temp) + Score(humidity) + Score(light)) / 4.0f;
}

} // namespace pof02
