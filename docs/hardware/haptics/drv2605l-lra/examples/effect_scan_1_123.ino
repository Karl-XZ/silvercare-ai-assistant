#include <Wire.h>
#include <Adafruit_DRV2605.h>

Adafruit_DRV2605 drv;
uint8_t effect = 1;

void setup() {
  Serial.begin(115200);
  Wire.begin(5, 6);
  if (!drv.begin()) {
    Serial.println("DRV2605L not found");
    while (1) delay(10);
  }
  drv.useLRA();
  drv.selectLibrary(6);
  drv.setMode(DRV2605_MODE_INTTRIG);
}

void loop() {
  Serial.printf("Effect %u\n", effect);
  drv.setWaveform(0, effect);
  drv.setWaveform(1, 0);
  drv.go();
  delay(900);
  effect++;
  if (effect > 123) effect = 1;
}
