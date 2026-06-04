/*
 *  CommTemplate.ino - LTE Communication Template for Low-Power Sensing
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

#ifdef SUBCORE
#error "Core selection is wrong!!"
#endif

#include <Arduino.h>
#include <MP.h>

#define MSG_FFT_RESULT (20)

const int imu_core = 1;
const int analyze_core = 2;

struct FftAnalysisResult {
  float peakHz;
};

void setup()
{
  Serial.begin(115200);
  while (!Serial) {
    ;
  }

  Serial.println("Starting .");

  int ret = MP.begin(imu_core);
  if (ret < 0) {
    printf("MP.begin(%d) error = %d\n", imu_core, ret);
  }

  ret = MP.begin(analyze_core);
  if (ret < 0) {
    printf("MP.begin(%d) error = %d\n", analyze_core, ret);
  }
}

void loop()
{
  int8_t msgid = 0;
  FftAnalysisResult *result = NULL;

  int ret = MP.Recv(&msgid, &result, analyze_core);
  if (ret <= 0 || msgid != MSG_FFT_RESULT || result == NULL) {
    return;
  }

  Serial.print("FFT peak_hz: ");
  Serial.println(result->peakHz, 3);
}
