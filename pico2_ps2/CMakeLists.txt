cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

if(NOT DEFINED PICO_BOARD)
    set(PICO_BOARD pico2 CACHE STRING "Board type")
endif()

include(C:/Users/robte/.pico-sdk/sdk/2.2.0/external/pico_sdk_import.cmake)

project(pico2_usb_ps2_tangnano C CXX ASM)

pico_sdk_init()

add_executable(pico2_usb_ps2_tangnano
    main.c
)

target_include_directories(pico2_usb_ps2_tangnano PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}
)

target_link_libraries(pico2_usb_ps2_tangnano PUBLIC
    pico_stdlib
    tinyusb_host
    tinyusb_board
)

pico_enable_stdio_usb(pico2_usb_ps2_tangnano 0)
pico_enable_stdio_uart(pico2_usb_ps2_tangnano 0)

pico_add_extra_outputs(pico2_usb_ps2_tangnano)
