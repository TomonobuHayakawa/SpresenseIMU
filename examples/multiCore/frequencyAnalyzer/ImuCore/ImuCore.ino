/*
 *  ImuCore.ino - FFT analysis sample for multi core.
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

#include <MP.h>
#include "SpresenseIMU.h"

#if (SUBCORE != 1)
#error "Core selection is wrong!!"
#endif

#define SAMPLINGRATE (1920)
#define ADRANGE      (4)
#define GDRANGE      (500)
#define FIFO_DEPTH   (1)
#define BLOCK_SIZE   (2048)
#define BUFFER_SIZE  (4)

#ifdef SUBCORE
USER_HEAP_SIZE(64 * 1024);
#endif

const int analyze_core = 2;

enum error_no {
  BEGIN_ERROR = 0,
  INIT_ERROR,
  STRAT_ERROR,
  SEND_ERROR
};

static pwbImuData sampleBlock[BUFFER_SIZE][BLOCK_SIZE];
static uint16_t sampleCount = 0;
static uint8_t bufferIndex = 0;

void errorLoop(int num)
{
  int i;

  printf("Subcore error %d\n", num);

  while (1) {
    for (i = 0; i < num; i++) {
      ledOn(LED0);
      delay(300);
      ledOff(LED0);
      delay(300);
    }
    delay(1000);
  }
}

void setup(void)
{
  MP.begin();

  int ret;
  ret = SpresenseIMU.begin();
  if (ret < 0) {
    printf("Spresense IMU begin.\n");
    errorLoop(BEGIN_ERROR);
  }

  ret = SpresenseIMU.initialize(SAMPLINGRATE, ADRANGE, GDRANGE, FIFO_DEPTH);
  if (!ret) {
    SpresenseIMU.end();
    errorLoop(INIT_ERROR);
  }

  ret = SpresenseIMU.start();
  if (!ret) {
    SpresenseIMU.finalize();
    SpresenseIMU.end();
    errorLoop(STRAT_ERROR);
  }

  sleep(1);
}

void loop()
{
  pwbImuData imu;

  if (SpresenseIMU.get(imu)) {
    sampleBlock[bufferIndex][sampleCount] = imu;
    sampleCount++;

    if (sampleCount >= BLOCK_SIZE) {
      int ret = MP.Send(10, MP.Virt2Phys(sampleBlock[bufferIndex]), analyze_core);
      if (ret < 0) {
        errorLoop(SEND_ERROR);
      }

      bufferIndex = (bufferIndex + 1) % BUFFER_SIZE;
      sampleCount = 0;
    }
  }
}
