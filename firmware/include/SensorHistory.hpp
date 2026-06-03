#pragma once

#include <cstddef>
#include <vector>

#include "PlantTypes.hpp"

namespace pof02 {

class SensorHistory {
public:
    explicit SensorHistory(std::size_t capacity);

    void Add(const SensorSnapshot& snapshot);
    std::size_t Size() const;
    bool Empty() const;
    const SensorSnapshot& Latest() const;
    const std::vector<SensorSnapshot>& Data() const;

private:
    std::size_t capacity_;
    std::vector<SensorSnapshot> data_;
};

} // namespace pof02
