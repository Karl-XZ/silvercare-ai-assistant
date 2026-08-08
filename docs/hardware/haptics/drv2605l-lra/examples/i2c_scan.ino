#include <Wire.h>

void setup() {
  Serial.begin(115200);
  Wire.begin(5, 6);  // XIAO ESP32-S3: SDA=GPIO5, SCL=GPIO6
  delay(100);

  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("Found I2C: 0x%02X\n", addr);
    }
  }
}

void loop() {}
