cmake_minimum_required(VERSION 3.16)
project(pof03_demo CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(
    pof03_demo
    src/main.cpp
    src/FileStorageService.cpp
    src/WiFiCommunication.cpp
    src/TimeService.cpp
    src/SoilMoistureSensor.cpp
    src/TempHumiditySensor.cpp
    src/LightSensor.cpp
    src/Classification.cpp
    src/Stress.cpp
    src/SensorHistory.cpp
    src/FeatureEngineering.cpp
    src/MLLayer.cpp
    src/RecommendationEngine.cpp
    src/MonitoringSystem.cpp)

target_include_directories(pof03_demo PRIVATE include)
