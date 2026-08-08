#include <Wire.h>
#include <Adafruit_DRV2605.h>

Adafruit_DRV2605 drv;

void pulse(uint8_t power, int ms) {
  drv.setRealtimeValue(power);
  delay(ms);
  drv.setRealtimeValue(0);
}

void setup() {
  Wire.begin(5, 6);
  if (!drv.begin()) while (1) delay(10);
  drv.useLRA();
  drv.setMode(DRV2605_MODE_REALTIME);
}

void loop() {
  // 仅用于体验相对触感；长期强度需在拿到 LRA 规格后校准。
  pulse(190, 70);
  delay(90);
  pulse(130, 55);
  delay(720);
}
