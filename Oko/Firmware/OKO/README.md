# OKO Water Meter Monitor - ESP32-S3 Firmware v2.2

## Required Libraries
Install via Arduino Library Manager:
1. **EloquentTinyML** (version >= 3.0.0)
2. **tflm_esp32**

## Board Settings
- Board: XIAO_ESP32S3
- PSRAM: OPI PSRAM (IMPORTANT!)
- Partition Scheme: Huge APP (3MB No OTA/1MB SPIFFS)
- Flash Mode: QIO 80MHz

## Files
- `OKO.ino` - Main firmware
- `watermeter_model.cpp/h` - Digit recognition model (48x64 RGB -> 11 classes)
- `gauge_model.cpp/h` - Gauge position model (128x96 RGB -> 0-1 position)

## Testing Without ML
Set `#define ML_ENABLED 0` at the top of OKO.ino to compile without models.

## Serial Commands
- `status` - Show current state
- `test_ml` - Run ML inference test
- `provision` - Re-enter provisioning mode
- `reset` - Factory reset

## Troubleshooting
If you get library conflicts:
1. Make sure ESP32 board package is 2.x (not 3.x) for EloquentTinyML compatibility
2. If still failing, try:
   - Arduino IDE > Tools > Partition Scheme > Huge APP
   - Verify PSRAM is enabled in board settings
