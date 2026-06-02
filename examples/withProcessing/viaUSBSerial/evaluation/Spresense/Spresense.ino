/*
 * Spresense.ino - Board evaluation sample on Spresense
 *  Author Interested-In-Spresense
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include "SpresenseIMU.h"

// ====== Settings ======
#define SAMPLINGRATE      (1920)   // Hz
#define ADRANGE           (4)      // [G]
#define GDRANGE           (500)    // [dps]
#define FIFO_DEPTH        (1)      // FIFO depth

#define RECORD_SEC        (3)
#define MAX_SAMPLES       (SAMPLINGRATE * RECORD_SEC)

// ====== Calibration settings ======
#define STARTUP_SETTLE_MS (3000)
#define CALIBRATION_MS    (3000)
#define PRE_CAPTURE_WAIT_MS (5000)

// ====== Buffer ======
static pwbImuData g_buf[MAX_SAMPLES];
static int g_count = 0;
static bool g_done = false;

static float g_gyroBias[3] = {0.0f, 0.0f, 0.0f};
static float g_trueGravity = 0.0f;

static void calibrateBiasAndGravity(int ms)
{
  printf("Keep still for calibration (%d ms)...\n", ms);

  double sumGx = 0.0;
  double sumGy = 0.0;
  double sumGz = 0.0;
  double sumAx = 0.0;
  double sumAy = 0.0;
  double sumAz = 0.0;
  int count = 0;

  unsigned long start = millis();
  while ((millis() - start) < (unsigned long)ms) {
    pwbImuData d;
    if (!SpresenseIMU.get(d)) {
      continue;
    }

    sumGx += d.data.gx;
    sumGy += d.data.gy;
    sumGz += d.data.gz;
    sumAx += d.data.ax;
    sumAy += d.data.ay;
    sumAz += d.data.az;
    count++;
  }

  if (count <= 0) {
    printf("[WARN] calibration skipped (no samples)\n");
    return;
  }

  g_gyroBias[0] = (float)(sumGx / (double)count);
  g_gyroBias[1] = (float)(sumGy / (double)count);
  g_gyroBias[2] = (float)(sumGz / (double)count);

  float ax = (float)(sumAx / (double)count);
  float ay = (float)(sumAy / (double)count);
  float az = (float)(sumAz / (double)count);
  g_trueGravity = sqrtf(ax * ax + ay * ay + az * az);

  printf("[Calibration Done] count=%d\n", count);
  printf("gyro_bias,%f,%f,%f\n", g_gyroBias[0], g_gyroBias[1], g_gyroBias[2]);
  printf("gravity_mag,%f\n", g_trueGravity);
}

void setup(void)
{
  int ret;

  ret = SpresenseIMU.begin();
  if (ret < 0) {
    printf("[FATAL] SpresenseIMU.begin() failed\n");
    return;
  }

  ret = SpresenseIMU.initialize(SAMPLINGRATE, ADRANGE, GDRANGE, FIFO_DEPTH);
  if (!ret) {
    printf("[FATAL] SpresenseIMU.initialize() failed (rate=%d)\n", SAMPLINGRATE);
    SpresenseIMU.end();
    return;
  }

  ret = SpresenseIMU.start();
  if (!ret) {
    printf("[FATAL] SpresenseIMU.start() failed\n");
    SpresenseIMU.finalize();
    SpresenseIMU.end();
    return;
  }

  delay(STARTUP_SETTLE_MS);
  calibrateBiasAndGravity(CALIBRATION_MS);
  printf("Waiting before capture (%d ms)...\n", PRE_CAPTURE_WAIT_MS);
  delay(PRE_CAPTURE_WAIT_MS);

  printf("=== eval_sample (with startup calibration) ===\n");
  printf("Capture: %d Hz x %d sec => %d samples\n", SAMPLINGRATE, RECORD_SEC, MAX_SAMPLES);
  printf("Start capture...\n");
}

static void dump_buffer(void)
{
  for (int i = 0; i < g_count; i++) {
    g_buf[i].print();
  }
}

void loop(void)
{
  if (g_done) {
    delay(1000);
    return;
  }

  pwbImuData imuData;

  if (SpresenseIMU.get(imuData)) {
    if (g_count < MAX_SAMPLES) {
      g_buf[g_count] = imuData;
      g_count++;
    }

    if (g_count >= MAX_SAMPLES) {

      SpresenseIMU.stop();

      printf("Capture done: %d samples\n", g_count);
      printf("Dump start...\n");
      dump_buffer();
      printf("Dump end.\n");

      SpresenseIMU.finalize();
      SpresenseIMU.end();

      g_done = true;
    }
  }
}
