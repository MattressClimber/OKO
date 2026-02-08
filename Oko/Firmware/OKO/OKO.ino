/*
 * OKO Water Meter Monitor - ESP32-S3 Firmware v2.5
 * Hardware: Seeed XIAO ESP32-S3 Sense
 * 
 * FEATURES: BLE provisioning, WiFi streaming, ML inference, deep sleep
 * 
 * BOARD SETTINGS:
 * - Board: XIAO_ESP32S3
 * - USB CDC On Boot: Enabled
 * - PSRAM: OPI PSRAM
 * - Partition: Huge APP (3MB No OTA/1MB SPIFFS)
 * 
 * CHANGELOG v2.5:
 * - Refactored for efficiency and reliability
 * - Improved memory management
 * - Better serial initialization for ESP32-S3
 * - Consolidated camera config
 * - Reduced code duplication
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <esp_camera.h>
#include <esp_sleep.h>
#include <esp_wifi.h>
#include <esp_mac.h>
#include "USB.h"

// ============================================================================
// CONFIGURATION
// ============================================================================

#define ML_ENABLED 1
#define FIRMWARE_VERSION "2.5.0"
#define DEVICE_NAME "Oko"

// Timing
#define STREAM_PORT 81
#define SPINNER_CHECK_INTERVAL_MIN 15
#define SPINNER_DIFF_THRESHOLD 1500
#define CONTINUOUS_FLOW_ALERT_MIN 60
#define BLE_FRAME_INTERVAL_MS 150
#define STATUS_UPDATE_INTERVAL_MS 3000
#define WIFI_CONNECT_TIMEOUT_MS 10000

// Camera pins - XIAO ESP32-S3 Sense
#define CAM_PIN_PWDN    -1
#define CAM_PIN_RESET   -1
#define CAM_PIN_XCLK    10
#define CAM_PIN_SIOD    40
#define CAM_PIN_SIOC    39
#define CAM_PIN_D7      48
#define CAM_PIN_D6      11
#define CAM_PIN_D5      12
#define CAM_PIN_D4      14
#define CAM_PIN_D3      16
#define CAM_PIN_D2      18
#define CAM_PIN_D1      17
#define CAM_PIN_D0      15
#define CAM_PIN_VSYNC   38
#define CAM_PIN_HREF    47
#define CAM_PIN_PCLK    13
#define LED_FLASH_PIN   21
#define BATTERY_PIN     1

// BLE UUIDs
#define SERVICE_UUID           "4F4B4F00-0001-0001-0001-4F4B4F444556"
#define CHAR_WIFI_LIST_UUID    "4F4B4F01-0001-0001-0001-4F4B4F444556"
#define CHAR_WIFI_CREDS_UUID   "4F4B4F02-0001-0001-0001-4F4B4F444556"
#define CHAR_WIFI_STATUS_UUID  "4F4B4F03-0001-0001-0001-4F4B4F444556"
#define CHAR_CAMERA_FRAME_UUID "4F4B4F04-0001-0001-0001-4F4B4F444556"
#define CHAR_CAMERA_CTRL_UUID  "4F4B4F05-0001-0001-0001-4F4B4F444556"
#define CHAR_ROI_CONFIG_UUID   "4F4B4F06-0001-0001-0001-4F4B4F444556"
#define CHAR_DEVICE_STATUS_UUID "4F4B4F07-0001-0001-0001-4F4B4F444556"
#define CHAR_DEVICE_CONFIG_UUID "4F4B4F08-0001-0001-0001-4F4B4F444556"
#define CHAR_COMMAND_UUID      "4F4B4F09-0001-0001-0001-4F4B4F444556"

// ML Configuration
#if ML_ENABLED
#include <tflm_esp32.h>
#include <eloquent_tinyml.h>
#include "watermeter_model.cpp"
#include "gauge_model.cpp"

#define NUM_OPS 10
#define DIGIT_INPUT_W 48
#define DIGIT_INPUT_H 64
#define DIGIT_INPUT_SIZE (DIGIT_INPUT_W * DIGIT_INPUT_H * 3)
#define DIGIT_NUM_CLASSES 11
#define GAUGE_INPUT_W 128
#define GAUGE_INPUT_H 96
#define GAUGE_INPUT_SIZE (GAUGE_INPUT_W * GAUGE_INPUT_H * 3)
#define DIGIT_ARENA_SIZE 80000
#define GAUGE_ARENA_SIZE 60000
#define NUM_METER_DIGITS 5
#endif

// ============================================================================
// DATA STRUCTURES
// ============================================================================

struct DeviceState {
  char wifiSSID[33];
  char wifiPassword[65];
  char deviceLabel[32];
  char deviceType[16];
  float dialRoiX, dialRoiY, dialRoiW, dialRoiH;
  float spinnerRoiX, spinnerRoiY, spinnerRoiW, spinnerRoiH;
  uint32_t lastReading;
  uint8_t batteryPercent;
  bool wifiConfigured;
  bool roiConfigured;
};

// RTC memory - persists across deep sleep
RTC_DATA_ATTR uint32_t rtcBootCount = 0;
RTC_DATA_ATTR uint32_t rtcWakeCount = 0;
RTC_DATA_ATTR uint32_t rtcFlowMinutes = 0;
RTC_DATA_ATTR uint32_t rtcConsecutiveFlow = 0;
RTC_DATA_ATTR uint32_t rtcLastDialReading = 0;
RTC_DATA_ATTR bool rtcAlertSent = false;

// ============================================================================
// GLOBALS
// ============================================================================

// BLE
BLEServer* pServer = nullptr;
BLECharacteristic* pWifiListChar = nullptr;
BLECharacteristic* pWifiCredsChar = nullptr;
BLECharacteristic* pWifiStatusChar = nullptr;
BLECharacteristic* pCameraFrameChar = nullptr;
BLECharacteristic* pCameraCtrlChar = nullptr;
BLECharacteristic* pRoiConfigChar = nullptr;
BLECharacteristic* pDeviceStatusChar = nullptr;
BLECharacteristic* pDeviceConfigChar = nullptr;
BLECharacteristic* pCommandChar = nullptr;

// State flags
volatile bool deviceConnected = false;
volatile bool bleStreamingEnabled = false;
bool oldDeviceConnected = false;
bool needsWifiScan = false;
bool cameraInitialized = false;
bool flashEnabled = false;
bool wifiStreamingActive = false;

// Objects
WebServer streamServer(STREAM_PORT);
Preferences preferences;
DeviceState state;
String deviceIP;

// Buffers
uint8_t* spinnerFrame1 = nullptr;
uint8_t* spinnerFrame2 = nullptr;

#if ML_ENABLED
uint8_t* mlInputBuffer = nullptr;
Eloquent::TF::Sequential<NUM_OPS, DIGIT_ARENA_SIZE>* pDigitModel = nullptr;
Eloquent::TF::Sequential<NUM_OPS, GAUGE_ARENA_SIZE>* pGaugeModel = nullptr;
bool digitModelLoaded = false;
bool gaugeModelLoaded = false;
#endif

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

inline void flashOn() { digitalWrite(LED_FLASH_PIN, HIGH); }
inline void flashOff() { digitalWrite(LED_FLASH_PIN, LOW); }

void log(const char* fmt, ...) {
  char buf[256];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  Serial.print(buf);
  Serial.flush();
}

void logln(const char* fmt, ...) {
  char buf[256];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  Serial.println(buf);
  Serial.flush();
}

uint8_t readBatteryPercent() {
  uint32_t sum = 0;
  for (int i = 0; i < 4; i++) {
    sum += analogRead(BATTERY_PIN);
    delay(2);
  }
  float voltage = (sum / 4.0 / 4095.0) * 3.3 * 2;
  return constrain((int)((voltage - 3.0) / 1.2 * 100), 0, 100);
}

void freeBuffer(uint8_t** buf) {
  if (*buf) { 
    free(*buf); 
    *buf = nullptr; 
  }
}

void freeSpinnerBuffers() {
  freeBuffer(&spinnerFrame1);
  freeBuffer(&spinnerFrame2);
}

// ============================================================================
// PREFERENCES
// ============================================================================

void loadState() {
  preferences.begin("oko", true);
  
  preferences.getString("ssid", state.wifiSSID, sizeof(state.wifiSSID));
  preferences.getString("pass", state.wifiPassword, sizeof(state.wifiPassword));
  preferences.getString("label", state.deviceLabel, sizeof(state.deviceLabel));
  preferences.getString("type", state.deviceType, sizeof(state.deviceType));
  
  state.wifiConfigured = preferences.getBool("wifiCfg", false);
  state.roiConfigured = preferences.getBool("roiCfg", false);
  
  state.dialRoiX = preferences.getFloat("dialX", 0.1f);
  state.dialRoiY = preferences.getFloat("dialY", 0.2f);
  state.dialRoiW = preferences.getFloat("dialW", 0.8f);
  state.dialRoiH = preferences.getFloat("dialH", 0.4f);
  
  state.spinnerRoiX = preferences.getFloat("spinX", 0.4f);
  state.spinnerRoiY = preferences.getFloat("spinY", 0.7f);
  state.spinnerRoiW = preferences.getFloat("spinW", 0.2f);
  state.spinnerRoiH = preferences.getFloat("spinH", 0.2f);
  
  state.lastReading = preferences.getUInt("reading", 0);
  
  preferences.end();
  
  if (!state.deviceType[0]) strcpy(state.deviceType, "Water");
}

void saveState() {
  preferences.begin("oko", false);
  
  preferences.putString("ssid", state.wifiSSID);
  preferences.putString("pass", state.wifiPassword);
  preferences.putString("label", state.deviceLabel);
  preferences.putString("type", state.deviceType);
  
  preferences.putBool("wifiCfg", state.wifiConfigured);
  preferences.putBool("roiCfg", state.roiConfigured);
  
  preferences.putFloat("dialX", state.dialRoiX);
  preferences.putFloat("dialY", state.dialRoiY);
  preferences.putFloat("dialW", state.dialRoiW);
  preferences.putFloat("dialH", state.dialRoiH);
  
  preferences.putFloat("spinX", state.spinnerRoiX);
  preferences.putFloat("spinY", state.spinnerRoiY);
  preferences.putFloat("spinW", state.spinnerRoiW);
  preferences.putFloat("spinH", state.spinnerRoiH);
  
  preferences.putUInt("reading", state.lastReading);
  
  preferences.end();
}

void resetDevice() {
  logln("Resetting device...");
  preferences.begin("oko", false);
  preferences.clear();
  preferences.end();
  rtcBootCount = rtcWakeCount = rtcLastDialReading = 0;
  rtcFlowMinutes = rtcConsecutiveFlow = 0;
  rtcAlertSent = false;
  delay(100);
  ESP.restart();
}

// ============================================================================
// CAMERA
// ============================================================================

bool initCamera(bool lowRes) {
  if (cameraInitialized) return true;
  
  logln("Initializing camera...");
  freeSpinnerBuffers();
  esp_camera_deinit();
  delay(50);
  
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = CAM_PIN_D0;
  config.pin_d1 = CAM_PIN_D1;
  config.pin_d2 = CAM_PIN_D2;
  config.pin_d3 = CAM_PIN_D3;
  config.pin_d4 = CAM_PIN_D4;
  config.pin_d5 = CAM_PIN_D5;
  config.pin_d6 = CAM_PIN_D6;
  config.pin_d7 = CAM_PIN_D7;
  config.pin_xclk = CAM_PIN_XCLK;
  config.pin_pclk = CAM_PIN_PCLK;
  config.pin_vsync = CAM_PIN_VSYNC;
  config.pin_href = CAM_PIN_HREF;
  config.pin_sccb_sda = CAM_PIN_SIOD;
  config.pin_sccb_scl = CAM_PIN_SIOC;
  config.pin_pwdn = CAM_PIN_PWDN;
  config.pin_reset = CAM_PIN_RESET;
  config.xclk_freq_hz = 20000000;
  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;
  config.fb_count = 2;
  
  if (lowRes) {
    config.frame_size = FRAMESIZE_QQVGA;
    config.pixel_format = PIXFORMAT_GRAYSCALE;
  } else {
    config.frame_size = FRAMESIZE_VGA;
    config.pixel_format = PIXFORMAT_JPEG;
    config.jpeg_quality = 12;
  }
  
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    log("Camera init failed: 0x%x\n", err);
    return false;
  }
  
  cameraInitialized = true;
  logln("Camera ready");
  return true;
}

bool initCameraForML() {
  if (cameraInitialized) {
    esp_camera_deinit();
    cameraInitialized = false;
    delay(50);
  }
  
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = CAM_PIN_D0;
  config.pin_d1 = CAM_PIN_D1;
  config.pin_d2 = CAM_PIN_D2;
  config.pin_d3 = CAM_PIN_D3;
  config.pin_d4 = CAM_PIN_D4;
  config.pin_d5 = CAM_PIN_D5;
  config.pin_d6 = CAM_PIN_D6;
  config.pin_d7 = CAM_PIN_D7;
  config.pin_xclk = CAM_PIN_XCLK;
  config.pin_pclk = CAM_PIN_PCLK;
  config.pin_vsync = CAM_PIN_VSYNC;
  config.pin_href = CAM_PIN_HREF;
  config.pin_sccb_sda = CAM_PIN_SIOD;
  config.pin_sccb_scl = CAM_PIN_SIOC;
  config.pin_pwdn = CAM_PIN_PWDN;
  config.pin_reset = CAM_PIN_RESET;
  config.xclk_freq_hz = 20000000;
  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.fb_count = 1;
  config.frame_size = FRAMESIZE_VGA;
  config.pixel_format = PIXFORMAT_RGB565;
  
  if (esp_camera_init(&config) != ESP_OK) {
    logln("Camera init for ML failed!");
    return false;
  }
  
  cameraInitialized = true;
  return true;
}

void deinitCamera() {
  if (cameraInitialized) {
    esp_camera_deinit();
    cameraInitialized = false;
  }
}

// ============================================================================
// WIFI STREAMING
// ============================================================================

void handleStreamCapture() {
  if (!cameraInitialized) {
    streamServer.send(503, "text/plain", "Camera not ready");
    return;
  }
  
  if (flashEnabled) {
    flashOn();
    delay(30);
  }
  
  camera_fb_t* fb = esp_camera_fb_get();
  if (flashEnabled) flashOff();
  
  if (!fb) {
    streamServer.send(500, "text/plain", "Capture failed");
    return;
  }
  
  streamServer.sendHeader("Access-Control-Allow-Origin", "*");
  streamServer.sendHeader("Cache-Control", "no-cache, no-store, must-revalidate");
  streamServer.send_P(200, "image/jpeg", (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
}

void handleFlashControl() {
  streamServer.sendHeader("Access-Control-Allow-Origin", "*");
  
  if (streamServer.hasArg("state")) {
    String s = streamServer.arg("state");
    flashEnabled = (s == "on" || s == "1" || s == "true");
    flashEnabled ? flashOn() : flashOff();
  }
  
  streamServer.send(200, "application/json", 
    flashEnabled ? "{\"flash\":true}" : "{\"flash\":false}");
}

void handleCORS() {
  streamServer.sendHeader("Access-Control-Allow-Origin", "*");
  streamServer.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  streamServer.sendHeader("Access-Control-Allow-Headers", "*");
  streamServer.send(204);
}

bool startWiFiStreaming() {
  if (WiFi.status() != WL_CONNECTED) return false;
  if (!cameraInitialized && !initCamera(false)) return false;
  
  streamServer.on("/capture", HTTP_GET, handleStreamCapture);
  streamServer.on("/capture", HTTP_OPTIONS, handleCORS);
  streamServer.on("/flash", HTTP_GET, handleFlashControl);
  streamServer.on("/flash", HTTP_OPTIONS, handleCORS);
  streamServer.begin();
  
  wifiStreamingActive = true;
  deviceIP = WiFi.localIP().toString();
  log("WiFi stream: http://%s:%d/capture\n", deviceIP.c_str(), STREAM_PORT);
  return true;
}

void stopWiFiStreaming() {
  if (wifiStreamingActive) {
    streamServer.stop();
    wifiStreamingActive = false;
  }
}

// ============================================================================
// BLE STREAMING
// ============================================================================

void sendFrameViaBLE(camera_fb_t* fb) {
  if (!fb || !deviceConnected || !pCameraFrameChar) return;
  
  const size_t chunkSize = 180;
  size_t totalPackets = (fb->len + chunkSize - 1) / chunkSize;
  
  // Send header
  char header[32];
  snprintf(header, sizeof(header), "FRAME:%d:%d", (int)totalPackets, (int)fb->len);
  pCameraFrameChar->setValue((uint8_t*)header, strlen(header));
  pCameraFrameChar->notify();
  delay(15);
  
  // Send data packets
  uint8_t packet[182];
  size_t offset = 0;
  uint16_t packetNum = 0;
  
  while (offset < fb->len && deviceConnected) {
    size_t chunkLen = min(chunkSize, fb->len - offset);
    
    packet[0] = packetNum >> 8;
    packet[1] = packetNum & 0xFF;
    memcpy(packet + 2, fb->buf + offset, chunkLen);
    
    pCameraFrameChar->setValue(packet, chunkLen + 2);
    pCameraFrameChar->notify();
    
    offset += chunkLen;
    packetNum++;
    delay(8);
  }
  
  // Send end marker
  pCameraFrameChar->setValue((uint8_t*)"FRAME_END", 9);
  pCameraFrameChar->notify();
}

void captureAndSendBLE() {
  if (!cameraInitialized && !initCamera(false)) return;
  
  if (flashEnabled) flashOn();
  camera_fb_t* fb = esp_camera_fb_get();
  if (flashEnabled) flashOff();
  
  if (fb) {
    sendFrameViaBLE(fb);
    esp_camera_fb_return(fb);
  }
}

// ============================================================================
// ML INFERENCE
// ============================================================================

#if ML_ENABLED

void extractROI(uint8_t* src, int srcW, int srcH, 
                float rx, float ry, float rw, float rh,
                uint8_t* dst, int dstW, int dstH) {
  int roiX = constrain((int)(rx * srcW), 0, srcW - 1);
  int roiY = constrain((int)(ry * srcH), 0, srcH - 1);
  int roiW = constrain((int)(rw * srcW), 1, srcW - roiX);
  int roiH = constrain((int)(rh * srcH), 1, srcH - roiY);
  
  for (int y = 0; y < dstH; y++) {
    int sy = constrain(roiY + (y * roiH / dstH), 0, srcH - 1);
    for (int x = 0; x < dstW; x++) {
      int sx = constrain(roiX + (x * roiW / dstW), 0, srcW - 1);
      int srcIdx = (sy * srcW + sx) * 2;
      
      // RGB565 to RGB888
      uint16_t pixel = (src[srcIdx] << 8) | src[srcIdx + 1];
      int dstIdx = (y * dstW + x) * 3;
      dst[dstIdx]     = ((pixel >> 11) & 0x1F) << 3;
      dst[dstIdx + 1] = ((pixel >> 5) & 0x3F) << 2;
      dst[dstIdx + 2] = (pixel & 0x1F) << 3;
    }
  }
}

bool initDigitModel() {
  if (digitModelLoaded) return true;
  
  logln("Loading digit model...");
  
  if (psramFound()) {
    pDigitModel = (Eloquent::TF::Sequential<NUM_OPS, DIGIT_ARENA_SIZE>*)
      ps_malloc(sizeof(Eloquent::TF::Sequential<NUM_OPS, DIGIT_ARENA_SIZE>));
  } else {
    pDigitModel = new Eloquent::TF::Sequential<NUM_OPS, DIGIT_ARENA_SIZE>();
  }
  
  if (!pDigitModel) {
    logln("Digit model alloc failed!");
    return false;
  }
  
  pDigitModel->setNumInputs(DIGIT_INPUT_SIZE);
  pDigitModel->setNumOutputs(DIGIT_NUM_CLASSES);
  pDigitModel->resolver.AddConv2D();
  pDigitModel->resolver.AddDepthwiseConv2D();
  pDigitModel->resolver.AddMaxPool2D();
  pDigitModel->resolver.AddAveragePool2D();
  pDigitModel->resolver.AddFullyConnected();
  pDigitModel->resolver.AddSoftmax();
  pDigitModel->resolver.AddReshape();
  pDigitModel->resolver.AddRelu();
  pDigitModel->resolver.AddRelu6();
  pDigitModel->resolver.AddPad();
  
  if (!pDigitModel->begin(digit_model_tflite).isOk()) {
    log("Digit model error: %s\n", pDigitModel->exception.toString());
    return false;
  }
  
  digitModelLoaded = true;
  logln("Digit model OK");
  return true;
}

bool initGaugeModel() {
  if (gaugeModelLoaded) return true;
  
  logln("Loading gauge model...");
  
  if (psramFound()) {
    pGaugeModel = (Eloquent::TF::Sequential<NUM_OPS, GAUGE_ARENA_SIZE>*)
      ps_malloc(sizeof(Eloquent::TF::Sequential<NUM_OPS, GAUGE_ARENA_SIZE>));
  } else {
    pGaugeModel = new Eloquent::TF::Sequential<NUM_OPS, GAUGE_ARENA_SIZE>();
  }
  
  if (!pGaugeModel) {
    logln("Gauge model alloc failed!");
    return false;
  }
  
  pGaugeModel->setNumInputs(GAUGE_INPUT_SIZE);
  pGaugeModel->setNumOutputs(1);
  pGaugeModel->resolver.AddConv2D();
  pGaugeModel->resolver.AddDepthwiseConv2D();
  pGaugeModel->resolver.AddMaxPool2D();
  pGaugeModel->resolver.AddAveragePool2D();
  pGaugeModel->resolver.AddFullyConnected();
  pGaugeModel->resolver.AddRelu();
  pGaugeModel->resolver.AddRelu6();
  pGaugeModel->resolver.AddReshape();
  pGaugeModel->resolver.AddPad();
  
  if (!pGaugeModel->begin(gauge_model_tflite).isOk()) {
    log("Gauge model error: %s\n", pGaugeModel->exception.toString());
    return false;
  }
  
  gaugeModelLoaded = true;
  logln("Gauge model OK");
  return true;
}

int classifyDigit(uint8_t* rgb) {
  if (!initDigitModel()) return -1;
  
  float* input = (float*)ps_malloc(DIGIT_INPUT_SIZE * sizeof(float));
  if (!input) return -1;
  
  for (int i = 0; i < DIGIT_INPUT_SIZE; i++) {
    input[i] = rgb[i] / 255.0f;
  }
  
  bool ok = pDigitModel->predict(input).isOk();
  free(input);
  
  if (!ok) return -1;
  
  float maxProb = 0;
  int maxClass = -1;
  for (int i = 0; i < DIGIT_NUM_CLASSES; i++) {
    float prob = pDigitModel->output(i);
    if (prob > maxProb) {
      maxProb = prob;
      maxClass = i;
    }
  }
  
  // Class 10 = unknown, or low confidence
  if (maxClass == 10 || maxProb < 0.5f) return -1;
  
  log("Digit: %d (%.0f%%)\n", maxClass, maxProb * 100);
  return maxClass;
}

float readGauge(uint8_t* rgb) {
  if (!initGaugeModel()) return -1;
  
  float* input = (float*)ps_malloc(GAUGE_INPUT_SIZE * sizeof(float));
  if (!input) return -1;
  
  for (int i = 0; i < GAUGE_INPUT_SIZE; i++) {
    input[i] = rgb[i] / 255.0f;
  }
  
  bool ok = pGaugeModel->predict(input).isOk();
  free(input);
  
  if (!ok) return -1;
  
  float result = constrain(pGaugeModel->output(0), 0.0f, 1.0f);
  log("Gauge: %.2f\n", result);
  return result;
}

#endif // ML_ENABLED

uint32_t readDialWithML() {
#if ML_ENABLED
  logln("Reading dial with ML...");
  log("Heap: %d, PSRAM: %d\n", ESP.getFreeHeap(), ESP.getFreePsram());
  
  // Allocate ML buffer if needed
  if (!mlInputBuffer) {
    size_t bufSize = max(DIGIT_INPUT_SIZE, GAUGE_INPUT_SIZE);
    mlInputBuffer = (uint8_t*)ps_malloc(bufSize);
    if (!mlInputBuffer) {
      logln("ML buffer alloc failed!");
      return rtcLastDialReading;
    }
  }
  
  // Initialize camera for RGB565 capture
  if (!initCameraForML()) {
    return rtcLastDialReading;
  }
  
  // Capture with flash
  flashOn();
  delay(50);
  camera_fb_t* fb = esp_camera_fb_get();
  flashOff();
  
  if (!fb) {
    logln("Capture failed!");
    deinitCamera();
    return rtcLastDialReading;
  }
  
  log("Captured: %dx%d\n", fb->width, fb->height);
  
  uint32_t reading = 0;
  bool isGauge = (strcmp(state.deviceType, "Gauge") == 0);
  
  if (isGauge) {
    extractROI(fb->buf, fb->width, fb->height,
               state.dialRoiX, state.dialRoiY, state.dialRoiW, state.dialRoiH,
               mlInputBuffer, GAUGE_INPUT_W, GAUGE_INPUT_H);
    
    float pos = readGauge(mlInputBuffer);
    reading = (pos >= 0) ? (uint32_t)(pos * 100) : rtcLastDialReading;
  } else {
    // Water meter - read digits left to right
    float digitWidth = state.dialRoiW / NUM_METER_DIGITS;
    bool allDigitsOK = true;
    
    for (int d = 0; d < NUM_METER_DIGITS && allDigitsOK; d++) {
      extractROI(fb->buf, fb->width, fb->height,
                 state.dialRoiX + d * digitWidth, state.dialRoiY,
                 digitWidth, state.dialRoiH,
                 mlInputBuffer, DIGIT_INPUT_W, DIGIT_INPUT_H);
      
      int digit = classifyDigit(mlInputBuffer);
      if (digit >= 0) {
        reading = reading * 10 + digit;
      } else {
        allDigitsOK = false;
        reading = rtcLastDialReading;
      }
    }
  }
  
  esp_camera_fb_return(fb);
  deinitCamera();
  
  rtcLastDialReading = reading;
  state.lastReading = reading;
  log("Reading: %d\n", reading);
  return reading;
  
#else
  return ++rtcLastDialReading;
#endif
}

// ============================================================================
// SPINNER MOTION DETECTION
// ============================================================================

bool checkSpinnerMotion() {
  logln("Checking spinner motion...");
  
  if (!initCamera(true)) return false;
  
  // Calculate ROI bounds
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    deinitCamera();
    return false;
  }
  
  int roiX = constrain((int)(state.spinnerRoiX * fb->width), 0, fb->width - 1);
  int roiY = constrain((int)(state.spinnerRoiY * fb->height), 0, fb->height - 1);
  int roiW = constrain((int)(state.spinnerRoiW * fb->width), 1, fb->width - roiX);
  int roiH = constrain((int)(state.spinnerRoiH * fb->height), 1, fb->height - roiY);
  size_t roiSize = roiW * roiH;
  
  // Allocate buffers
  if (!spinnerFrame1) spinnerFrame1 = (uint8_t*)malloc(roiSize);
  if (!spinnerFrame2) spinnerFrame2 = (uint8_t*)malloc(roiSize);
  
  if (!spinnerFrame1 || !spinnerFrame2) {
    esp_camera_fb_return(fb);
    freeSpinnerBuffers();
    deinitCamera();
    return false;
  }
  
  // Capture frame 1
  flashOn();
  delay(30);
  
  for (int y = 0; y < roiH; y++) {
    for (int x = 0; x < roiW; x++) {
      spinnerFrame1[y * roiW + x] = fb->buf[(roiY + y) * fb->width + roiX + x];
    }
  }
  esp_camera_fb_return(fb);
  
  // Wait and capture frame 2
  delay(2000);
  
  fb = esp_camera_fb_get();
  flashOff();
  
  if (!fb) {
    deinitCamera();
    return false;
  }
  
  for (int y = 0; y < roiH; y++) {
    for (int x = 0; x < roiW; x++) {
      spinnerFrame2[y * roiW + x] = fb->buf[(roiY + y) * fb->width + roiX + x];
    }
  }
  esp_camera_fb_return(fb);
  deinitCamera();
  
  // Calculate difference
  uint32_t diff = 0;
  for (size_t i = 0; i < roiSize; i++) {
    diff += abs((int)spinnerFrame1[i] - (int)spinnerFrame2[i]);
  }
  
  bool isSpinning = diff > SPINNER_DIFF_THRESHOLD;
  log("Spinner diff: %d, spinning: %s\n", diff, isSpinning ? "YES" : "NO");
  
  if (isSpinning) {
    rtcConsecutiveFlow++;
    rtcFlowMinutes += SPINNER_CHECK_INTERVAL_MIN;
  } else {
    rtcConsecutiveFlow = 0;
  }
  
  return isSpinning;
}

// ============================================================================
// ALERTS
// ============================================================================

void checkForAlerts() {
  uint32_t flowThreshold = CONTINUOUS_FLOW_ALERT_MIN / SPINNER_CHECK_INTERVAL_MIN;
  
  if (rtcConsecutiveFlow >= flowThreshold) {
    if (!rtcAlertSent) {
      log("ALERT: Continuous flow for %d+ minutes!\n", rtcFlowMinutes);
      // TODO: Send alert via WiFi/cloud
      rtcAlertSent = true;
    }
  } else {
    rtcAlertSent = false;
  }
}

// ============================================================================
// WIFI
// ============================================================================

void scanAndSendWiFiNetworks() {
  logln("Scanning WiFi...");
  
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  
  int n = WiFi.scanNetworks();
  
  String json = "[";
  for (int i = 0; i < n && i < 15; i++) {
    if (i > 0) json += ",";
    json += "{\"ssid\":\"";
    json += WiFi.SSID(i);
    json += "\",\"rssi\":";
    json += WiFi.RSSI(i);
    json += ",\"secure\":";
    json += (WiFi.encryptionType(i) != WIFI_AUTH_OPEN) ? "true" : "false";
    json += "}";
  }
  json += "]";
  
  WiFi.scanDelete();
  
  if (deviceConnected && pWifiListChar) {
    pWifiListChar->setValue(json.c_str());
    pWifiListChar->notify();
  }
  
  log("Found %d networks\n", n);
}

bool connectWiFi(const char* ssid, const char* password) {
  log("Connecting to %s...\n", ssid);
  
  WiFi.begin(ssid, password);
  
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_CONNECT_TIMEOUT_MS) {
    delay(250);
    if (!deviceConnected) return false; // BLE disconnected
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    deviceIP = WiFi.localIP().toString();
    log("Connected! IP: %s\n", deviceIP.c_str());
    return true;
  }
  
  logln("WiFi connection failed");
  return false;
}

// ============================================================================
// BLE STATUS
// ============================================================================

void sendDeviceStatus() {
  state.batteryPercent = readBatteryPercent();
  
  char json[384];
  snprintf(json, sizeof(json),
    "{\"battery\":%d,"
    "\"wifiConfigured\":%s,"
    "\"wifiConnected\":%s,"
    "\"ssid\":\"%s\","
    "\"ip\":\"%s\","
    "\"roiConfigured\":%s,"
    "\"lastReading\":%d,"
    "\"mlEnabled\":%s,"
    "\"version\":\"%s\"}",
    state.batteryPercent,
    state.wifiConfigured ? "true" : "false",
    WiFi.status() == WL_CONNECTED ? "true" : "false",
    state.wifiSSID,
    WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString().c_str() : "",
    state.roiConfigured ? "true" : "false",
    state.lastReading,
    ML_ENABLED ? "true" : "false",
    FIRMWARE_VERSION
  );
  
  if (deviceConnected && pDeviceStatusChar) {
    pDeviceStatusChar->setValue(json);
    pDeviceStatusChar->notify();
  }
}

// ============================================================================
// BLE CALLBACKS
// ============================================================================

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    deviceConnected = true;
    needsWifiScan = true;
    logln("BLE connected");
  }
  
  void onDisconnect(BLEServer* s) override {
    deviceConnected = false;
    bleStreamingEnabled = false;
    logln("BLE disconnected");
  }
};

class WifiCredsCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String value = c->getValue().c_str();
    int sep = value.indexOf(':');
    
    if (sep > 0) {
      value.substring(0, sep).toCharArray(state.wifiSSID, sizeof(state.wifiSSID));
      value.substring(sep + 1).toCharArray(state.wifiPassword, sizeof(state.wifiPassword));
      
      if (pWifiStatusChar) {
        pWifiStatusChar->setValue("{\"status\":\"connecting\"}");
        pWifiStatusChar->notify();
      }
      
      if (connectWiFi(state.wifiSSID, state.wifiPassword)) {
        state.wifiConfigured = true;
        saveState();
        
        char response[128];
        snprintf(response, sizeof(response),
          "{\"status\":\"connected\",\"ip\":\"%s\",\"ssid\":\"%s\"}",
          deviceIP.c_str(), state.wifiSSID);
        
        if (pWifiStatusChar) {
          pWifiStatusChar->setValue(response);
          pWifiStatusChar->notify();
        }
      } else {
        state.wifiConfigured = false;
        saveState();
        
        if (pWifiStatusChar) {
          pWifiStatusChar->setValue("{\"status\":\"failed\",\"error\":\"Connection failed\"}");
          pWifiStatusChar->notify();
        }
      }
    }
  }
};

class CameraCtrlCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String cmd = c->getValue().c_str();
    
    if (cmd == "start_stream") {
      if (WiFi.status() == WL_CONNECTED && startWiFiStreaming()) {
        char response[96];
        snprintf(response, sizeof(response),
          "{\"mode\":\"wifi\",\"url\":\"http://%s:%d/capture\"}",
          deviceIP.c_str(), STREAM_PORT);
        pCameraFrameChar->setValue(response);
      } else {
        bleStreamingEnabled = true;
        pCameraFrameChar->setValue("{\"mode\":\"ble\"}");
      }
      pCameraFrameChar->notify();
    }
    else if (cmd == "stop_stream") {
      bleStreamingEnabled = false;
      stopWiFiStreaming();
      flashEnabled = false;
      flashOff();
    }
    else if (cmd == "flash_on") {
      flashEnabled = true;
      flashOn();
    }
    else if (cmd == "flash_off") {
      flashEnabled = false;
      flashOff();
    }
  }
};

class RoiConfigCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String value = c->getValue().c_str();
    
    // Format: "dial:x,y,w,h;spinner:x,y,w,h"
    if (value.startsWith("dial:")) {
      int semi = value.indexOf(';');
      if (semi > 0) {
        float dx, dy, dw, dh, sx, sy, sw, sh;
        
        if (sscanf(value.substring(5, semi).c_str(), "%f,%f,%f,%f", &dx, &dy, &dw, &dh) == 4 &&
            sscanf(value.substring(semi + 9).c_str(), "%f,%f,%f,%f", &sx, &sy, &sw, &sh) == 4) {
          
          state.dialRoiX = dx; state.dialRoiY = dy;
          state.dialRoiW = dw; state.dialRoiH = dh;
          state.spinnerRoiX = sx; state.spinnerRoiY = sy;
          state.spinnerRoiW = sw; state.spinnerRoiH = sh;
          state.roiConfigured = true;
          saveState();
          
          logln("ROI configured");
        }
      }
    }
  }
};

class DeviceConfigCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String value = c->getValue().c_str();
    int sep = value.indexOf(':');
    
    if (sep > 0) {
      value.substring(0, sep).toCharArray(state.deviceLabel, sizeof(state.deviceLabel));
      value.substring(sep + 1).toCharArray(state.deviceType, sizeof(state.deviceType));
      saveState();
      log("Device: %s (%s)\n", state.deviceLabel, state.deviceType);
    }
  }
};

class CommandCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String cmd = c->getValue().c_str();
    
    if (cmd == "scan_wifi") {
      scanAndSendWiFiNetworks();
    }
    else if (cmd == "get_status") {
      sendDeviceStatus();
    }
    else if (cmd == "test_ml" || cmd == "read_dial") {
      readDialWithML();
    }
    else if (cmd == "reset") {
      resetDevice();
    }
  }
};

// ============================================================================
// BLE SETUP
// ============================================================================

void setupBLE() {
  uint8_t mac[6];
  esp_efuse_mac_get_default(mac);
  
  char deviceName[24];
  snprintf(deviceName, sizeof(deviceName), "%s_%02X%02X", DEVICE_NAME, mac[4], mac[5]);
  
  BLEDevice::init(deviceName);
  BLEDevice::setMTU(185);
  
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  BLEService* service = pServer->createService(BLEUUID(SERVICE_UUID), 32);
  
  // WiFi characteristics
  pWifiListChar = service->createCharacteristic(
    CHAR_WIFI_LIST_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pWifiListChar->addDescriptor(new BLE2902());
  
  pWifiCredsChar = service->createCharacteristic(
    CHAR_WIFI_CREDS_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pWifiCredsChar->setCallbacks(new WifiCredsCallback());
  
  pWifiStatusChar = service->createCharacteristic(
    CHAR_WIFI_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pWifiStatusChar->addDescriptor(new BLE2902());
  
  // Camera characteristics
  pCameraFrameChar = service->createCharacteristic(
    CHAR_CAMERA_FRAME_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCameraFrameChar->addDescriptor(new BLE2902());
  
  pCameraCtrlChar = service->createCharacteristic(
    CHAR_CAMERA_CTRL_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCameraCtrlChar->setCallbacks(new CameraCtrlCallback());
  
  // Config characteristics
  pRoiConfigChar = service->createCharacteristic(
    CHAR_ROI_CONFIG_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pRoiConfigChar->setCallbacks(new RoiConfigCallback());
  
  pDeviceStatusChar = service->createCharacteristic(
    CHAR_DEVICE_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pDeviceStatusChar->addDescriptor(new BLE2902());
  
  pDeviceConfigChar = service->createCharacteristic(
    CHAR_DEVICE_CONFIG_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );
  pDeviceConfigChar->setCallbacks(new DeviceConfigCallback());
  
  pCommandChar = service->createCharacteristic(
    CHAR_COMMAND_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCommandChar->setCallbacks(new CommandCallback());
  
  service->start();
  
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  
  log("BLE ready: %s\n", deviceName);
}

void stopBLE() {
  BLEDevice::deinit(true);
}

// ============================================================================
// DEEP SLEEP
// ============================================================================

void enterDeepSleep(uint64_t sleepTimeUs) {
  logln("Entering deep sleep...");
  
  saveState();
  freeSpinnerBuffers();
  
  #if ML_ENABLED
  freeBuffer(&mlInputBuffer);
  #endif
  
  deinitCamera();
  stopWiFiStreaming();
  WiFi.disconnect(true);
  stopBLE();
  
  esp_sleep_enable_timer_wakeup(sleepTimeUs);
  esp_deep_sleep_start();
}

// ============================================================================
// SERIAL COMMANDS
// ============================================================================

void handleSerialCommands() {
  while (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    cmd.toLowerCase();
    
    if (cmd.length() == 0) continue;
    
    if (cmd == "reset" || cmd == "r") {
      resetDevice();
    }
    else if (cmd == "provision" || cmd == "p") {
      state.wifiConfigured = false;
      state.roiConfigured = false;
      saveState();
      ESP.restart();
    }
    else if (cmd == "test" || cmd == "t" || cmd == "read") {
      readDialWithML();
    }
    else if (cmd == "status" || cmd == "s") {
      log("WiFi: %s (%s), ROI: %s, Reading: %d, Battery: %d%%\n",
        state.wifiConfigured ? "yes" : "no",
        state.wifiSSID,
        state.roiConfigured ? "yes" : "no",
        state.lastReading,
        readBatteryPercent());
      log("Heap: %d, PSRAM: %d\n", ESP.getFreeHeap(), ESP.getFreePsram());
    }
    else if (cmd == "help" || cmd == "h" || cmd == "?") {
      logln("Commands: reset, provision, test, status, help");
    }
    else {
      log("Unknown: %s\n", cmd.c_str());
    }
  }
}

// ============================================================================
// MAIN MODES
// ============================================================================

void runProvisioningMode() {
  logln("=== Provisioning Mode ===");
  setupBLE();
  
  unsigned long lastStatusTime = 0;
  unsigned long lastFrameTime = 0;
  unsigned long connectTime = 0;
  bool wifiScanned = false;
  
  while (true) {
    // Handle disconnect -> restart advertising
    if (!deviceConnected && oldDeviceConnected) {
      delay(300);
      BLEDevice::startAdvertising();
      deinitCamera();
      stopWiFiStreaming();
      wifiScanned = false;
    }
    
    // Handle new connection
    if (deviceConnected && !oldDeviceConnected) {
      connectTime = millis();
      wifiScanned = false;
    }
    
    oldDeviceConnected = deviceConnected;
    
    // Auto WiFi scan after connection settles
    if (deviceConnected && needsWifiScan && !wifiScanned && millis() - connectTime > 800) {
      scanAndSendWiFiNetworks();
      wifiScanned = true;
      needsWifiScan = false;
      delay(50);
      sendDeviceStatus();
    }
    
    // BLE streaming
    if (bleStreamingEnabled && deviceConnected && !wifiStreamingActive) {
      if (!cameraInitialized) initCamera(false);
      
      if (millis() - lastFrameTime >= BLE_FRAME_INTERVAL_MS) {
        captureAndSendBLE();
        lastFrameTime = millis();
      }
    }
    
    // WiFi streaming
    if (wifiStreamingActive) {
      streamServer.handleClient();
    }
    
    // Periodic status update
    if (deviceConnected && millis() - lastStatusTime >= STATUS_UPDATE_INTERVAL_MS) {
      sendDeviceStatus();
      lastStatusTime = millis();
    }
    
    // Check if setup complete
    if (state.wifiConfigured && state.roiConfigured) {
      logln("Setup complete!");
      stopWiFiStreaming();
      deinitCamera();
      delay(500);
      break;
    }
    
    handleSerialCommands();
    delay(5);
  }
}

void runNormalOperation() {
  logln("=== Normal Operation ===");
  
  // Check spinner motion
  checkSpinnerMotion();
  
  // Read dial every 16th wake (4 hours at 15 min intervals)
  if (rtcWakeCount % 16 == 0) {
    readDialWithML();
  }
  
  // Check for continuous flow alerts
  checkForAlerts();
  
  // Save state and sleep
  saveState();
  enterDeepSleep((uint64_t)SPINNER_CHECK_INTERVAL_MIN * 60ULL * 1000000ULL);
}

// ============================================================================
// SETUP & LOOP
// ============================================================================

void setup() {
  // Initialize USB Serial for ESP32-S3
  USB.begin();
  Serial.begin(115200);
  
  // Wait for serial connection
  delay(1500);
  unsigned long serialWait = millis();
  while (!Serial && millis() - serialWait < 3000) {
    delay(50);
  }
  delay(500);
  
  // Header
  Serial.println();
  logln("========================================");
  log("  OKO Water Meter Monitor v%s\n", FIRMWARE_VERSION);
  log("  ML: %s | PSRAM: %s\n", 
      ML_ENABLED ? "ON" : "OFF",
      psramFound() ? "OK" : "NO");
  log("  Heap: %dKB | PSRAM: %dKB\n",
      ESP.getFreeHeap() / 1024,
      psramFound() ? ESP.getFreePsram() / 1024 : 0);
  logln("========================================");
  
  // Initialize hardware
  pinMode(LED_FLASH_PIN, OUTPUT);
  flashOff();
  analogReadResolution(12);
  
  // Load saved state
  loadState();
  rtcWakeCount++;
  
  // Brief window for serial commands
  logln("Type 'help' for commands (2s)...");
  unsigned long cmdWindow = millis();
  while (millis() - cmdWindow < 2000) {
    handleSerialCommands();
    delay(10);
  }
  
  // Run appropriate mode
  if (!state.wifiConfigured || !state.roiConfigured) {
    runProvisioningMode();
  }
  
  runNormalOperation();
}

void loop() {
  // Should not reach here in normal operation (deep sleep)
  handleSerialCommands();
  delay(100);
}
