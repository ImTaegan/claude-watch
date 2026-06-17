#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>

static const char* SERVICE_UUID = "c1a0de00-0001-4a00-b000-000000000001";
static const char* STATUS_UUID  = "c1a0de00-0002-4a00-b000-000000000002";

enum { ST_IDLE = 0, ST_RUNNING = 1, ST_DONE = 2, ST_NEEDS = 3 };

struct Status {
  int u = 0, r = 0, d = 0, i = 0;
  String top = "";
  int n = 0;
  String proj[5];
  int pstate[5];
  bool valid = false;
} g_status;

// portMUX-guarded fixed-buffer handoff (cross-core data-race hardening)
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;
static char g_rxBuf[256];
volatile bool g_dirty = false;
volatile bool g_connected = false;

class StatusCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    std::string v = c->getValue();  // NimBLEAttValue -> std::string deep copy
    portENTER_CRITICAL(&g_mux);
    strncpy(g_rxBuf, v.c_str(), sizeof(g_rxBuf) - 1);
    g_rxBuf[sizeof(g_rxBuf) - 1] = 0;
    g_dirty = true;
    portEXIT_CRITICAL(&g_mux);
  }
};

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*) override { g_connected = true; }
  void onDisconnect(NimBLEServer*) override {
    g_connected = false;
    NimBLEDevice::startAdvertising();
  }
};

uint16_t stateColor(int st) {
  switch (st) {
    case ST_NEEDS:   return M5.Display.color565(255, 176, 0);
    case ST_DONE:    return M5.Display.color565(0, 200, 80);
    case ST_RUNNING: return M5.Display.color565(0, 120, 255);
    default:         return M5.Display.color565(90, 90, 90);
  }
}

const char* stateLabel(int st) {
  switch (st) {
    case ST_NEEDS:   return "NEEDS INPUT";
    case ST_DONE:    return "DONE";
    case ST_RUNNING: return "RUNNING";
    default:         return "IDLE";
  }
}

int mostUrgent() {
  if (g_status.u > 0) return ST_NEEDS;
  if (g_status.d > 0) return ST_DONE;
  if (g_status.r > 0) return ST_RUNNING;
  return ST_IDLE;
}

void parseStatus(const char* s) {
  JsonDocument doc;
  if (deserializeJson(doc, s)) return;
  g_status.u = doc["u"] | 0;
  g_status.r = doc["r"] | 0;
  g_status.d = doc["d"] | 0;
  g_status.i = doc["i"] | 0;
  g_status.top = String((const char*)(doc["top"] | ""));
  g_status.n = 0;
  for (JsonObject o : doc["sessions"].as<JsonArray>()) {
    if (g_status.n >= 5) break;
    g_status.proj[g_status.n] = String((const char*)(o["project"] | "?"));
    g_status.pstate[g_status.n] = o["state"] | 0;
    g_status.n++;
  }
  g_status.valid = true;
}

void renderSummary() {
  int st = mostUrgent();
  uint16_t bg = stateColor(st);
  M5.Display.fillScreen(bg);
  M5.Display.setTextColor(TFT_BLACK, bg);
  M5.Display.setTextSize(2);
  M5.Display.setCursor(6, 10);
  M5.Display.print(stateLabel(st));
  M5.Display.setCursor(6, 48);
  M5.Display.print(g_status.top);
  M5.Display.setTextSize(2);
  M5.Display.setCursor(6, 206);
  M5.Display.printf("R%d N%d D%d", g_status.r, g_status.u, g_status.d);
}

int g_view = 0;  // 0 = summary, 1 = detail

void renderDetail() {
  M5.Display.fillScreen(TFT_BLACK);
  M5.Display.setTextColor(TFT_WHITE, TFT_BLACK);
  M5.Display.setTextSize(2);
  M5.Display.setCursor(4, 4);
  M5.Display.print("Sessions");
  int y = 36;
  for (int k = 0; k < g_status.n; k++) {
    M5.Display.setTextColor(stateColor(g_status.pstate[k]), TFT_BLACK);
    M5.Display.setCursor(4, y);
    M5.Display.printf("%s:%s", g_status.proj[k].c_str(),
                      stateLabel(g_status.pstate[k]));
    y += 34;
  }
  if (g_status.n == 0) {
    M5.Display.setTextColor(TFT_WHITE, TFT_BLACK);
    M5.Display.setCursor(4, y);
    M5.Display.print("(none)");
  }
}

void render() {
  if (g_view == 1) renderDetail();
  else renderSummary();
}

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Display.setRotation(0);
  renderSummary();

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
  if (M5.BtnA.wasPressed()) { g_view = 1; render(); }
  if (M5.BtnB.wasPressed()) { g_view = 0; render(); }
  char rx[256];
  bool have = false;
  portENTER_CRITICAL(&g_mux);
  if (g_dirty) { memcpy(rx, g_rxBuf, sizeof(rx)); g_dirty = false; have = true; }
  portEXIT_CRITICAL(&g_mux);
  if (have) {
    parseStatus(rx);
    render();
  }
  delay(20);
}
