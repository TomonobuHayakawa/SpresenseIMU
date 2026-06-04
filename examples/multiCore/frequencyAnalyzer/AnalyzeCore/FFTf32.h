/*
 *  FFTf32.h - FFT Library for float32
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

#ifndef _FFTF32_H_
#define _FFTF32_H_

#include <FFT.h>
#include <arm_math.h>

template <int MAX_CHNUM, int FFTLEN>
class FFTf32 : public FFTClass<MAX_CHNUM, FFTLEN>
{
public:
  FFTf32() : m_ready(false) {}

  bool beginF32(windowType_t type = WindowHamming)
  {
    createCoef(type);
    m_ready = initFft();
    return m_ready;
  }

  bool ready() const
  {
    return m_ready;
  }

  bool fftAmpF32(const float *input, float *mag)
  {
    if (!m_ready || !input || !mag) {
      return false;
    }

    for (int i = 0; i < FFTLEN; i++) {
      m_workIn[i] = input[i] * m_coef[i];
    }

    arm_rfft_fast_f32(&m_fft, m_workIn, m_workOut, 0);
    mag[0] = fabsf(m_workOut[0]);
    arm_cmplx_mag_f32(&m_workOut[2], &mag[1], FFTLEN / 2 - 1);
    mag[FFTLEN / 2] = fabsf(m_workOut[1]);

    return true;
  }

private:
  arm_rfft_fast_instance_f32 m_fft;
  float m_coef[FFTLEN];
  float m_workIn[FFTLEN];
  float m_workOut[FFTLEN];
  bool m_ready;

  void createCoef(windowType_t type)
  {
    for (int i = 0; i < FFTLEN / 2; i++) {
      float c = 1.0f;
      if (type == WindowHamming) {
        c = 0.54f - (0.46f * arm_cos_f32(2.0f * PI * (float)i / (FFTLEN - 1)));
      } else if (type == WindowHanning) {
        c = 0.5f - (0.5f * arm_cos_f32(2.0f * PI * (float)i / (FFTLEN - 1)));
      }
      m_coef[i] = c;
      m_coef[FFTLEN - 1 - i] = c;
    }
  }

  bool initFft()
  {
    arm_status st = ARM_MATH_ARGUMENT_ERROR;

    switch (FFTLEN) {
      case 32:
        st = arm_rfft_32_fast_init_f32(&m_fft);
        break;
      case 64:
        st = arm_rfft_64_fast_init_f32(&m_fft);
        break;
      case 128:
        st = arm_rfft_128_fast_init_f32(&m_fft);
        break;
      case 256:
        st = arm_rfft_256_fast_init_f32(&m_fft);
        break;
      case 512:
        st = arm_rfft_512_fast_init_f32(&m_fft);
        break;
      case 1024:
        st = arm_rfft_1024_fast_init_f32(&m_fft);
        break;
      case 2048:
        st = arm_rfft_2048_fast_init_f32(&m_fft);
        break;
      case 4096:
        st = arm_rfft_4096_fast_init_f32(&m_fft);
        break;
      default:
        st = ARM_MATH_ARGUMENT_ERROR;
        break;
    }

    return (st == ARM_MATH_SUCCESS);
  }
};

#endif