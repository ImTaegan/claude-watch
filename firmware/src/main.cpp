#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>

static const char* SERVICE_UUID = "c1a0de00-0001-4a00-b000-000000000001";
static const char* STATUS_UUID  = "c1a0de00-0002-4a00-b000-000000000002";

volatile bool g_dirty = false;
volatile bool g_connected = false;
std::string g_rx;

class StatusCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    g_rx = c->getValue();
    g_dirty = true;
  }
};

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*) override { g_connected = true; }
  void onDisconnect(NimBLEServer*) override {
    g_connected = false;
    NimBLEDevice::startAdvertising();
  }
};

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Display.setRotation(0);
  M5.Display.fillScreen(M5.Display.color565(90, 90, 90));
  M5.Display.setTextSize(2);
  M5.Display.setCursor(4, 4);
  M5.Display.print("ClaudeWatch");

  NimBLEDevice::init("ClaudeWatch");
  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCb());
  NimBLEService* svc = server->createService(SERVICE_UUID);
  NimBLECharacteristic* ch = svc->createCharacteristic(
      STATUS_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  ch->setCallbacks(new StatusCb());
  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();
}

void loop() {
  M5.update();
  if (g_dirty) {
    g_dirty = false;
    JsonDocument doc;
    if (!deserializeJson(doc, g_rx)) {
      int u = doc["u"] | 0, r = doc["r"] | 0, d = doc["d"] | 0;
      uint16_t color = M5.Display.color565(90, 90, 90);     // idle grey
      if (u > 0)      color = M5.Display.color565(255, 176, 0);  // amber
      else if (d > 0) color = M5.Display.color565(0, 200, 80);   // green
      else if (r > 0) color = M5.Display.color565(0, 120, 255);  // blue
      M5.Display.fillScreen(color);
    }
  }
  delay(20);
}
