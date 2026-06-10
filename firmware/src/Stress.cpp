/**
 * @file Stress.cpp
 * @brief Implementation of Stress. Combined plant stress score computed from individual sensor levels.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "Stress.hpp"

float Stress::Score(Level level)
{
    switch (level)
    {
    case Level::kOk:
        return 0.0f;
    case Level::kLow:
    case Level::kHigh:
        return 1.0f;
    }
    return 1.0f;
}

float Stress::Combined(Level moisture, Level temp, Level humidity, Level light)
{
    return (Score(moisture) + Score(temp) + Score(humidity) + Score(light)) / 4.0f;
}
