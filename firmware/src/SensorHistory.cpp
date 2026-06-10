/**
 * @file SensorHistory.cpp
 * @brief Implementation of SensorHistory. Fixed-capacity ring buffer of sensor snapshots.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "SensorHistory.hpp"

#include <stdexcept>

SensorHistory::SensorHistory(std::size_t capacity) : capacity_(capacity)
{
    data_.reserve(capacity);
}

void SensorHistory::Add(const SensorSnapshot &snapshot)
{
    if (data_.size() == capacity_)
    {
        data_.erase(data_.begin());
    }
    data_.push_back(snapshot);
}

std::size_t SensorHistory::Size() const { return data_.size(); }

bool SensorHistory::Empty() const { return data_.empty(); }

const SensorSnapshot &SensorHistory::Latest() const
{
    if (data_.empty())
    {
        throw std::runtime_error("SensorHistory is empty");
    }
    return data_.back();
}

const std::vector<SensorSnapshot> &SensorHistory::Data() const { return data_; }
