#pragma once

/**
 * @brief A class for managing file storage operations.
 */
class LightSensor
{
public:
    /**
     * @brief Constructs a LightSensor instance.
     * @param pin The analog pin to which the light sensor is connected.
     */
    explicit LightSensor(int pin);

    /**
     * @brief Reads the light level as a percentage.
     * @return The light level percentage (0 = dark, 100 = max ADC brightness).
     */
    float ReadLightLevelPct() const;

private:
    int pin_;
};
