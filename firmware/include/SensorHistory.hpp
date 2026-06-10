/**
 * @file SensorHistory.hpp
 * @brief Fixed-capacity ring buffer of sensor snapshots.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <cstddef>
#include <vector>

#include "PlantTypes.hpp"

/**
 * @brief Stores a rolling window of sensor snapshots up to a fixed capacity.
 * Older entries are discarded when the buffer is full.
 */
class SensorHistory
{
public:
    /**
     * @brief Constructs a history buffer with the given capacity.
     * @param capacity Maximum number of snapshots to retain.
     */
    explicit SensorHistory(std::size_t capacity);

    /**
     * @brief Appends a snapshot, discarding the oldest entry if at capacity.
     * @param snapshot Snapshot to add.
     */
    void Add(const SensorSnapshot &snapshot);

    /** @return Number of snapshots currently stored. */
    std::size_t Size() const;

    /** @return @c true if no snapshots are stored. */
    bool Empty() const;

    /** @return The most recently added snapshot. */
    const SensorSnapshot &Latest() const;

    /** @return Read-only view of all stored snapshots, oldest first. */
    const std::vector<SensorSnapshot> &Data() const;

private:
    std::size_t capacity_;
    std::vector<SensorSnapshot> data_;
};
