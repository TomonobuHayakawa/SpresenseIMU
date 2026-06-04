/*
 *  AnalyzeCore.ino - Interpolation and FFT analysis sample for multi core.
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
#include "FFTf32.h"

#if (SUBCORE != 2)
#error "Core selection is wrong!!"
#endif

#define BLOCK_SIZE    (2048)
#define SAMPLINGRATE  (1920)
#define MSG_FFT_RESULT (20)

static float interpAx[BLOCK_SIZE];
static float interpAy[BLOCK_SIZE];
static float interpAz[BLOCK_SIZE];
static float analysisInput[BLOCK_SIZE];
static float fftMag[BLOCK_SIZE / 2 + 1];
static FFTf32<1, BLOCK_SIZE> fftF32;

struct FftAnalysisResult {
  float peakHz;
};

void errorLoop(int num);

static float getPeakFrequency(const float *mag, int fftLen, float fs)
{
  uint32_t index = 0;
  float maxValue = 0.0f;

  arm_max_f32((float *)&mag[1], fftLen / 2 - 1, &maxValue, &index);
  index += 1;

  if (index == 0 || index >= (uint32_t)(fftLen / 2)) {
    return (float)index * fs / (float)fftLen;
  }

  const float ym1 = mag[index - 1];
  const float y0 = mag[index];
  const float yp1 = mag[index + 1];
  const float denom = ym1 - 2.0f * y0 + yp1;

  float delta = 0.0f;
  if (fabsf(denom) > 1e-12f) {
    delta = 0.5f * (ym1 - yp1) / denom;
  }

  return ((float)index + delta) * fs / (float)fftLen;
}

static bool executeFft(float *mag)
{
  if (!fftF32.ready()) {
    return false;
  }

  float mean = 0.0f;
  for (int i = 0; i < BLOCK_SIZE; i++) {
    const float ax = interpAx[i];
    const float ay = interpAy[i];
    const float az = interpAz[i];
    analysisInput[i] = sqrtf(ax * ax + ay * ay + az * az);
    mean += analysisInput[i];
  }
  mean /= (float)BLOCK_SIZE;

  for (int i = 0; i < BLOCK_SIZE; i++) {
    analysisInput[i] = analysisInput[i] - mean;
  }

  return fftF32.fftAmpF32(analysisInput, mag);
}

static bool processInterpolatedBlock(const pwbImuData *sampleBlock)
{
  const uint16_t blockSize = BLOCK_SIZE;
  const uint64_t startTs = sampleBlock[0].data.timestamp;
  const uint64_t endTs = sampleBlock[blockSize - 1].data.timestamp;

  if (endTs <= startTs) {
    return false;
  }

  for (uint16_t i = 0; i < (blockSize - 1); i++) {
    const uint64_t avgIntervalTs = startTs + ((endTs - startTs) * i) / (blockSize - 1);

    const pwbImuData &a = sampleBlock[i];
    const pwbImuData &b = sampleBlock[i + 1];

    const uint64_t ta = a.data.timestamp;
    const uint64_t tb = b.data.timestamp;

    if (tb <= ta) {
      interpAx[i] = a.data.ax;
      interpAy[i] = a.data.ay;
      interpAz[i] = a.data.az;
    } else {
      const float r = (float)(avgIntervalTs - ta) / (float)(tb - ta);
      interpAx[i] = a.data.ax + (b.data.ax - a.data.ax) * r;
      interpAy[i] = a.data.ay + (b.data.ay - a.data.ay) * r;
      interpAz[i] = a.data.az + (b.data.az - a.data.az) * r;
    }
  }

  interpAx[blockSize - 1] = sampleBlock[blockSize - 1].data.ax;
  interpAy[blockSize - 1] = sampleBlock[blockSize - 1].data.ay;
  interpAz[blockSize - 1] = sampleBlock[blockSize - 1].data.az;

  return true;
}

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
  fftF32.beginF32(WindowHanning);
  sleep(1);
}

void loop()
{
  int8_t msgid = 0;
  uint32_t addr = 0;

  int ret = MP.Recv(&msgid, &addr, 1);
  if (ret <= 0 || msgid != 10) {
    return;
  }

  pwbImuData *sampleBlock = (pwbImuData *)addr;
  if (!processInterpolatedBlock(sampleBlock)) {
    return;
  }

  if (!executeFft(fftMag)) {
    return;
  }

  FftAnalysisResult result;
  result.peakHz = getPeakFrequency(fftMag, BLOCK_SIZE, (float)SAMPLINGRATE);

  ret = MP.Send(MSG_FFT_RESULT, (void *)&result);
  if (ret < 0) {
    errorLoop(6);
  }
}
