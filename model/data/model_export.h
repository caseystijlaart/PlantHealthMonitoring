#pragma once

static constexpr int POF02_FEATURE_COUNT = 12;
static constexpr const char* POF02_FEATURE_ORDER[12] = { "soil_now", "moisture_mean", "moisture_delta", "moisture_slope", "dry_duration", "temp_now", "humidity_now", "light_now", "hour_sin", "hour_cos", "dow_sin", "dow_cos" };

static constexpr float POF02_SCALER_MEAN[12] = { 45.06313250f, 46.54384750f, -1.21331875f, -1.11230083f, 0.20958833f, 22.99466875f, 64.47453958f, 439.35660875f, -0.28721443f, -0.17860960f, 0.02910828f, -0.00719158f };
static constexpr float POF02_SCALER_STD[12] = { 14.18808879f, 13.63243374f, 2.06060867f, 1.29093203f, 0.42378265f, 4.16045494f, 8.80557513f, 342.91102464f, 0.61675177f, 0.71079093f, 0.70086155f, 0.71266688f };
