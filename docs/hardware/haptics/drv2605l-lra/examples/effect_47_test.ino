#include <Wire.h>
#include <Adafruit_DRV2605.h>

Adafruit_DRV2605 drv;

void setup() {
  Serial.begin(115200);
  Wire.begin(5, 6);  // SDA=GPIO5, SCL=GPIO6

  if (!drv.begin()) {
    Serial.println("DRV2605L not found");
    while (1) delay(10);
  }

  Serial.println("DRV2605L connected");
  drv.useLRA();
  drv.selectLibrary(6);
  drv.setMode(DRV2605_MODE_INTTRIG);
  drv.setWaveform(0, 47);
  drv.setWaveform(1, 0);
  Serial.println("Vibrate!");
  drv.go();
}

void loop() {}
