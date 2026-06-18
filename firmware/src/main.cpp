#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include <math.h>

static const char* SERVICE_UUID = "c1a0de00-0001-4a00-b000-000000000001";
static const char* STATUS_UUID  = "c1a0de00-0002-4a00-b000-000000000002";

enum { ST_IDLE = 0, ST_RUNNING = 1, ST_DONE = 2, ST_NEEDS = 3 };
#define MASC_DISC 4   // mascot-only "disconnected" expression (not a session state)

// ---- landscape layout ----
static const int SCRW = 240, SCRH = 135;
static const int MW   = 90;   // mascot panel width (left); info panel is MW..240

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

// off-screen canvas for the mascot panel (avoids flicker during animation)
M5Canvas g_spr(&M5.Display);

// palette (filled in initColors after M5.begin)
uint16_t COL_BG, COL_BG2, COL_DIM, COL_ORANGE, COL_ORANGE_DIM, COL_ORANGE_GREY, COL_EYE;

void initColors() {
  COL_BG          = M5.Display.color565(22, 22, 28);
  COL_BG2         = M5.Display.color565(44, 44, 52);
  COL_DIM         = M5.Display.color565(74, 74, 86);
  COL_ORANGE      = M5.Display.color565(236, 130, 86);
  COL_ORANGE_DIM  = M5.Display.color565(150, 92, 64);
  COL_ORANGE_GREY = M5.Display.color565(122, 112, 110);
  COL_EYE         = M5.Display.color565(34, 18, 10);
}

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
    case ST_RUNNING: return M5.Display.color565(0, 150, 255);
    default:         return M5.Display.color565(110, 110, 122);
  }
}

const char* stateLabel(int st) {
  switch (st) {
    case ST_NEEDS:   return "NEEDS YOU";
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

// ----------------------------------------------------------------------------
// Mascot: an orange "Claude sunburst" whose face reacts to the agent state.
// Drawn into the off-screen sprite g_spr (size MW x SCRH), then pushed at (0,0).
// ----------------------------------------------------------------------------
void drawSunburst(M5Canvas& g, int cx, int cy, uint16_t col, int frame, int st) {
  const int n = 12;
  float rin = 17.0f, rout = 31.0f;
  float rot = 0.0f;
  if (st == ST_RUNNING) {            // spin + gentle pulse while working
    rot  = frame * 0.20f;
    rout = 29.0f + ((frame % 2) ? 4.0f : 0.0f);
  }
  const float aw = 0.17f;
  for (int k = 0; k < n; k++) {
    float a = rot + k * (2.0f * PI / n);
    int x0 = cx + cosf(a - aw) * rin, y0 = cy + sinf(a - aw) * rin;
    int x1 = cx + cosf(a + aw) * rin, y1 = cy + sinf(a + aw) * rin;
    int xt = cx + cosf(a) * rout,     yt = cy + sinf(a) * rout;
    g.fillTriangle(x0, y0, x1, y1, xt, yt, col);
  }
}

void drawMascot(M5Canvas& g, int st, int frame) {
  g.fillSprite(COL_BG);

  uint16_t body = COL_ORANGE;
  if (st == ST_IDLE)      body = COL_ORANGE_DIM;
  if (st == MASC_DISC)    body = COL_ORANGE_GREY;

  int cx = MW / 2, cy = 64;
  if (st == ST_NEEDS) cx += (frame % 2) ? 3 : -3;   // excited wiggle

  drawSunburst(g, cx, cy, body, frame, st);
  g.fillCircle(cx, cy, 20, body);

  const uint16_t E = COL_EYE;
  switch (st) {
    case ST_RUNNING: {
      g.fillCircle(cx - 7, cy - 2, 3, E);
      g.fillCircle(cx + 7, cy - 2, 3, E);
      g.fillCircle(cx, cy + 8, 2, E);                 // focused mouth
      int lit = frame % 4;                            // thinking dots
      for (int d = 0; d < 3; d++) {
        uint16_t c = (d < lit) ? TFT_WHITE : COL_BG2;
        g.fillCircle(cx + 16 + d * 8, cy - 22, 2, c);
      }
      break;
    }
    case ST_DONE: {
      g.drawLine(cx - 10, cy - 1, cx - 7, cy - 4, E);  // ^ ^ happy eyes
      g.drawLine(cx - 7, cy - 4, cx - 4, cy - 1, E);
      g.drawLine(cx + 4, cy - 1, cx + 7, cy - 4, E);
      g.drawLine(cx + 7, cy - 4, cx + 10, cy - 1, E);
      g.fillArc(cx, cy + 2, 6, 9, 20, 160, E);         // smile
      break;
    }
    case ST_NEEDS: {
      g.fillCircle(cx - 7, cy - 2, 4, TFT_WHITE);      // wide eyes
      g.fillCircle(cx - 7, cy - 2, 2, E);
      g.fillCircle(cx + 7, cy - 2, 4, TFT_WHITE);
      g.fillCircle(cx + 7, cy - 2, 2, E);
      g.drawCircle(cx, cy + 8, 3, E);                  // "o" mouth
      g.fillRoundRect(cx - 7, cy - 42, 15, 19, 4, TFT_WHITE);  // "!" bubble
      g.setTextColor(stateColor(ST_NEEDS), TFT_WHITE);
      g.setFont(&fonts::FreeSansBold9pt7b);
      g.setTextDatum(middle_center);
      g.drawString("!", cx, cy - 32);
      break;
    }
    case MASC_DISC: {
      g.drawLine(cx - 10, cy - 5, cx - 4, cy + 1, E);  // X eyes
      g.drawLine(cx - 10, cy + 1, cx - 4, cy - 5, E);
      g.drawLine(cx + 4, cy - 5, cx + 10, cy + 1, E);
      g.drawLine(cx + 4, cy + 1, cx + 10, cy - 5, E);
      g.drawLine(cx - 4, cy + 9, cx + 4, cy + 9, E);   // flat mouth
      break;
    }
    default: {  // ST_IDLE — sleeping
      g.drawLine(cx - 10, cy - 2, cx - 4, cy - 2, E);
      g.drawLine(cx + 4, cy - 2, cx + 10, cy - 2, E);
      g.drawLine(cx - 3, cy + 8, cx + 3, cy + 8, E);
      g.setTextColor(COL_ORANGE, COL_BG);
      g.setFont(&fonts::FreeSansBold9pt7b);
      g.setTextDatum(middle_center);
      g.drawString("z", cx + 20, cy - 20);
      g.drawString("z", cx + 28, cy - 28);
      break;
    }
  }
  g.pushSprite(0, 0);
}

// ----------------------------------------------------------------------------
// Info panel (right of the mascot): state label, top project, count pills.
// Drawn directly on the display so mascot animation never disturbs it.
// ----------------------------------------------------------------------------
void drawPill(int x, int y, uint16_t col, int count, int kind) {
  const int w = 42, h = 32, r = 9;
  bool on = count > 0;
  uint16_t fg = on ? TFT_BLACK : COL_DIM;
  if (on) M5.Display.fillRoundRect(x, y, w, h, r, col);
  else    M5.Display.drawRoundRect(x, y, w, h, r, COL_DIM);

  int my = y + h / 2;
  if (kind == ST_RUNNING) {                 // play triangle
    M5.Display.fillTriangle(x + 8, my - 5, x + 8, my + 5, x + 15, my, fg);
  } else if (kind == ST_NEEDS) {            // bang
    M5.Display.setFont(&fonts::FreeSansBold9pt7b);
    M5.Display.setTextDatum(middle_center);
    M5.Display.setTextColor(fg, on ? col : COL_BG);
    M5.Display.drawString("!", x + 11, my);
  } else {                                  // check mark
    M5.Display.drawLine(x + 7, my, x + 11, my + 5, fg);
    M5.Display.drawLine(x + 11, my + 5, x + 17, my - 5, fg);
  }

  char buf[6];
  snprintf(buf, sizeof(buf), "%d", count);
  M5.Display.setFont(&fonts::FreeSansBold9pt7b);
  M5.Display.setTextDatum(middle_right);
  M5.Display.setTextColor(fg, on ? col : COL_BG);
  M5.Display.drawString(buf, x + w - 7, my);
}

void drawInfoPanel(int st) {
  M5.Display.fillRect(MW, 0, SCRW - MW, SCRH, COL_BG);
  M5.Display.fillRect(MW, 0, 3, SCRH, stateColor(st));   // accent divider

  int x0 = MW + 10;
  M5.Display.setTextColor(stateColor(st), COL_BG);
  M5.Display.setFont(&fonts::FreeSansBold12pt7b);
  M5.Display.setTextDatum(top_left);
  M5.Display.drawString(stateLabel(st), x0, 12);

  String top = g_status.top;
  if (top.length() == 0) top = "-";
  if (top.length() > 14) top = top.substring(0, 13) + "..";
  M5.Display.setTextColor(TFT_WHITE, COL_BG);
  M5.Display.setFont(&fonts::FreeSans9pt7b);
  M5.Display.drawString(top, x0, 44);

  int py = 88;
  drawPill(MW + 8,  py, stateColor(ST_RUNNING), g_status.r, ST_RUNNING);
  drawPill(MW + 56, py, stateColor(ST_NEEDS),   g_status.u, ST_NEEDS);
  drawPill(MW + 104, py, stateColor(ST_DONE),   g_status.d, ST_DONE);
}

int g_view = 0;  // 0 = summary, 1 = detail
int g_frame = 0;
uint32_t g_lastFrameMs = 0;

void renderSummary() {
  int st = mostUrgent();
  drawMascot(g_spr, st, g_frame);
  drawInfoPanel(st);
}

void renderDetail() {
  M5.Display.fillScreen(COL_BG);
  M5.Display.setTextColor(COL_ORANGE, COL_BG);
  M5.Display.setFont(&fonts::FreeSansBold9pt7b);
  M5.Display.setTextDatum(top_left);
  M5.Display.drawString("SESSIONS", 8, 6);

  int y = 30;
  M5.Display.setFont(&fonts::FreeSans9pt7b);
  if (g_status.n == 0) {
    M5.Display.setTextColor(COL_DIM, COL_BG);
    M5.Display.drawString("(none)", 8, y);
    return;
  }
  for (int k = 0; k < g_status.n; k++) {
    M5.Display.fillCircle(12, y + 8, 4, stateColor(g_status.pstate[k]));
    String p = g_status.proj[k];
    if (p.length() > 13) p = p.substring(0, 12) + "..";
    M5.Display.setTextColor(TFT_WHITE, COL_BG);
    M5.Display.setTextDatum(top_left);
    M5.Display.drawString(p, 24, y);
    M5.Display.setTextColor(stateColor(g_status.pstate[k]), COL_BG);
    M5.Display.setTextDatum(top_right);
    M5.Display.drawString(stateLabel(g_status.pstate[k]), SCRW - 6, y);
    y += 21;
  }
}

void render() {
  if (g_view == 1) renderDetail();
  else renderSummary();
}

int g_lastUrgent = -1;
bool g_wasConnected = true;

void renderDisconnected() {
  M5.Display.fillScreen(COL_BG);
  drawMascot(g_spr, MASC_DISC, 0);
  M5.Display.fillRect(MW, 0, 3, SCRH, COL_ORANGE_GREY);
  int x0 = MW + 10;
  M5.Display.setTextColor(COL_ORANGE_GREY, COL_BG);
  M5.Display.setFont(&fonts::FreeSansBold12pt7b);
  M5.Display.setTextDatum(top_left);
  M5.Display.drawString("OFFLINE", x0, 18);
  M5.Display.setTextColor(TFT_WHITE, COL_BG);
  M5.Display.setFont(&fonts::FreeSans9pt7b);
  M5.Display.drawString("waiting for", x0, 54);
  M5.Display.drawString("daemon...", x0, 76);
}

void flashNeedsInput() {
  M5.Display.fillScreen(stateColor(ST_NEEDS));
  delay(110);
}

void selfTest() {
  int seq[] = {ST_IDLE, ST_RUNNING, ST_DONE, ST_NEEDS};
  for (int k = 0; k < 4; k++) {
    M5.Display.fillRect(MW, 0, SCRW - MW, SCRH, COL_BG);
    drawMascot(g_spr, seq[k], k);
    M5.Display.fillRect(MW, 0, 3, SCRH, stateColor(seq[k]));
    M5.Display.setTextColor(stateColor(seq[k]), COL_BG);
    M5.Display.setFont(&fonts::FreeSansBold12pt7b);
    M5.Display.setTextDatum(top_left);
    M5.Display.drawString(stateLabel(seq[k]), MW + 10, 50);
    delay(650);
  }
}

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Display.setRotation(1);            // landscape 240x135
  initColors();
  g_spr.setColorDepth(16);
  g_spr.createSprite(MW, SCRH);

  M5.update();
  if (M5.BtnB.isPressed()) selfTest();
  renderDisconnected();                 // boot = not yet connected to daemon

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

  if (g_connected != g_wasConnected) {
    g_wasConnected = g_connected;
    if (g_connected) render();
    else renderDisconnected();
  }

  if (M5.BtnA.wasPressed()) { g_view = 1; render(); }
  if (M5.BtnB.wasPressed()) { g_view = 0; render(); }

  char rx[256];
  bool have = false;
  portENTER_CRITICAL(&g_mux);
  if (g_dirty) { memcpy(rx, g_rxBuf, sizeof(rx)); g_dirty = false; have = true; }
  portEXIT_CRITICAL(&g_mux);
  if (have) {
    parseStatus(rx);
    int urgent = mostUrgent();
    if (urgent == ST_NEEDS && g_lastUrgent != ST_NEEDS && g_view == 0) {
      flashNeedsInput();
    }
    g_lastUrgent = urgent;
    if (g_connected) render();
  }

  // animate the mascot (working spin / needs wiggle) without redrawing text
  if (g_view == 0 && g_connected) {
    int st = mostUrgent();
    if ((st == ST_RUNNING || st == ST_NEEDS) && millis() - g_lastFrameMs > 170) {
      g_lastFrameMs = millis();
      g_frame++;
      drawMascot(g_spr, st, g_frame);
    }
  }

  delay(20);
}
