// ============================================
// Spresense raw IMU CSV log visualizer
// Input line format:
//   timestamp,temp,ax,ay,az,gx,gy,gz
// ============================================

final int FFT_POINTS = 1024;
final int PEAK_EXCLUSION_BINS = 3;
final int PEAK_DISPLAY_COUNT = 4;

// ===== Graph mode switch =====
// Set GRAPH_MODE to GRAPH_MODE_AMPLITUDE, GRAPH_MODE_POWER, or GRAPH_MODE_BOTH
final int GRAPH_MODE_AMPLITUDE = 0;
final int GRAPH_MODE_POWER = 1;
final int GRAPH_MODE_BOTH = 2;
final int GRAPH_MODE = GRAPH_MODE_POWER;

final int FOOTER_HEIGHT = 52;
final int COMBINED_PANEL_HEIGHT = 110;
final int PANEL_GAP = 10;

final float FIXED_SAMPLE_RATE_HZ = 1920.0;
final boolean USE_ESTIMATED_FS = false;

String loadedFilePath = "(not loaded)";
String statusText = "Press L to load raw CSV log file";

int totalLines = 0;
int parsedLines = 0;

int channelMode = 0; // 0:AX 1:AY 2:AZ 3:GX 4:GY 5:GZ 6:AMAG 7:GMAG
float sampleRateHz = FIXED_SAMPLE_RATE_HZ;

FloatList signal = new FloatList();
FloatList axList = new FloatList();
FloatList ayList = new FloatList();
FloatList azList = new FloatList();
FloatList gxList = new FloatList();
FloatList gyList = new FloatList();
FloatList gzList = new FloatList();
FloatList amagList = new FloatList();
FloatList gmagList = new FloatList();
FloatList accelCombinedFreqs = new FloatList();
FloatList accelCombinedAmps = new FloatList();
FloatList gyroCombinedFreqs = new FloatList();
FloatList gyroCombinedAmps = new FloatList();
FloatList fftFreqs = new FloatList();
FloatList fftAmps = new FloatList();
FloatList[] axisFftFreqs = new FloatList[6];
FloatList[] axisFftAmps = new FloatList[6];

float signalMean = Float.NaN;
float signalVar = Float.NaN;
float signalStd = Float.NaN;
float specMeanFreq = Float.NaN;
float specVarFreq = Float.NaN;
float specStdFreq = Float.NaN;

int[] topBins = new int[PEAK_DISPLAY_COUNT];
float[] topFreqHz = new float[PEAK_DISPLAY_COUNT];
float[] topAmp = new float[PEAK_DISPLAY_COUNT];
float[] topPower = new float[PEAK_DISPLAY_COUNT];
float[] gmagTopFreqHz = new float[PEAK_DISPLAY_COUNT];
float[] gmagTopPower = new float[PEAK_DISPLAY_COUNT];

float[] axisPeakFreqHz = new float[6];
float[] axisPeakPower = new float[6];
String[] axisNames = {"AX", "AY", "AZ", "GX", "GY", "GZ"};

float accelPeakFreqHz = Float.NaN;
float accelPeakPower = Float.NaN;
float gyroPeakFreqHz = Float.NaN;
float gyroPeakPower = Float.NaN;
float accelTotalPower = Float.NaN;
float gyroTotalPower = Float.NaN;

String graphModeName() {
  if (GRAPH_MODE == GRAPH_MODE_POWER) return "POWER";
  if (GRAPH_MODE == GRAPH_MODE_BOTH) return "BOTH";
  return "AMPLITUDE";
}

void setup() {
  size(1200, 760);
  frameRate(60);
  textFont(createFont("Consolas", 14));
  for (int i = 0; i < 6; i++) {
    axisFftFreqs[i] = new FloatList();
    axisFftAmps[i] = new FloatList();
  }
  selectInput("Select raw CSV log file", "fileSelected");
}

void draw() {
  background(18);
  drawHeader();

  int contentX = 20;
  int contentW = width - 40;
  int gridY = 230;
  int gridH = height - 250 - FOOTER_HEIGHT - (COMBINED_PANEL_HEIGHT * 2) - (PANEL_GAP * 2);
  if (gridH < 120) gridH = 120;

  drawSixAxisGrid(contentX, gridY, contentW, gridH);
  int combinedY = gridY + gridH + PANEL_GAP;
  drawCombinedAccelSpectrum(contentX, combinedY, contentW, COMBINED_PANEL_HEIGHT);
  drawCombinedGyroSpectrum(contentX, combinedY + COMBINED_PANEL_HEIGHT + PANEL_GAP, contentW, COMBINED_PANEL_HEIGHT);
  drawFooterPower(20, height - FOOTER_HEIGHT, width - 40, FOOTER_HEIGHT);
}

void fileSelected(File selection) {
  if (selection == null) {
    statusText = "File selection canceled";
    return;
  }
  loadRawLog(selection.getAbsolutePath());
}

void resetData() {
  totalLines = 0;
  parsedLines = 0;
  sampleRateHz = FIXED_SAMPLE_RATE_HZ;

  signal.clear();
  axList.clear();
  ayList.clear();
  azList.clear();
  gxList.clear();
  gyList.clear();
  gzList.clear();
  amagList.clear();
  gmagList.clear();
  accelCombinedFreqs.clear();
  accelCombinedAmps.clear();
  gyroCombinedFreqs.clear();
  gyroCombinedAmps.clear();
  fftFreqs.clear();
  fftAmps.clear();

  signalMean = Float.NaN;
  signalVar = Float.NaN;
  signalStd = Float.NaN;
  specMeanFreq = Float.NaN;
  specVarFreq = Float.NaN;
  specStdFreq = Float.NaN;

  for (int i = 0; i < PEAK_DISPLAY_COUNT; i++) {
    topBins[i] = -1;
    topFreqHz[i] = Float.NaN;
    topAmp[i] = Float.NaN;
    topPower[i] = Float.NaN;
    gmagTopFreqHz[i] = Float.NaN;
    gmagTopPower[i] = Float.NaN;
  }

  for (int i = 0; i < 6; i++) {
    axisPeakFreqHz[i] = Float.NaN;
    axisPeakPower[i] = Float.NaN;
    axisFftFreqs[i].clear();
    axisFftAmps[i].clear();
  }

  accelPeakFreqHz = Float.NaN;
  accelPeakPower = Float.NaN;
  gyroPeakFreqHz = Float.NaN;
  gyroPeakPower = Float.NaN;
  accelTotalPower = Float.NaN;
  gyroTotalPower = Float.NaN;
}

void loadRawLog(String path) {
  String[] lines = loadStrings(path);
  if (lines == null) {
    statusText = "Failed to load file";
    return;
  }

  loadedFilePath = path;
  resetData();

  String[] payload = extractPayloadLines(lines);

  FloatList timestamps = new FloatList();
  int invalidLines = 0;

  for (int i = 0; i < payload.length; i++) {
    String line = trim(payload[i]);
    if (line.length() == 0 || line.startsWith("===") || line.startsWith("Capture") || line.startsWith("Start") || line.startsWith("Dump")) {
      continue;
    }

    totalLines++;

    float[] parsed = parseImuLine(line);
    if (parsed == null) {
      invalidLines++;
      continue;
    }

    float ts = parsed[0];
    float ax = parsed[1];
    float ay = parsed[2];
    float az = parsed[3];
    float gx = parsed[4];
    float gy = parsed[5];
    float gz = parsed[6];
    if (Float.isNaN(ts) || Float.isNaN(ax) || Float.isNaN(ay) || Float.isNaN(az) || Float.isNaN(gx) || Float.isNaN(gy) || Float.isNaN(gz)) {
      invalidLines++;
      continue;
    }

    timestamps.append(ts);
    axList.append(ax);
    ayList.append(ay);
    azList.append(az);
    gxList.append(gx);
    gyList.append(gy);
    gzList.append(gz);
    amagList.append(sqrt(ax * ax + ay * ay + az * az));
    gmagList.append(sqrt(gx * gx + gy * gy + gz * gz));
    parsedLines++;
  }

  estimateFs(timestamps);
  rebuildSignalForChannel();
  runFftAndStats();
  computeSixAxisSpectra();
  statusText = "Loaded raw CSV: samples=" + signal.size() + ", parsed=" + parsedLines + ", skipped=" + invalidLines;
}

String[] extractPayloadLines(String[] lines) {
  if (lines == null || lines.length == 0) {
    return new String[0];
  }

  int start = 0;
  int end = lines.length;

  for (int i = 0; i < lines.length; i++) {
    String line = trim(lines[i]);
    if (line.startsWith("Dump start")) {
      start = i + 1;
      break;
    }
  }

  for (int i = start; i < lines.length; i++) {
    String line = trim(lines[i]);
    if (line.startsWith("Dump end")) {
      end = i;
      break;
    }
  }

  for (int i = start; i < end; i++) {
    String line = trim(lines[i]).toLowerCase();
    if (line.startsWith("timestamp,temp,ax,ay,az,gx,gy,gz")) {
      start = i + 1;
      break;
    }
  }

  if (start < 0) start = 0;
  if (end > lines.length) end = lines.length;
  if (start >= end) return new String[0];

  String[] out = new String[end - start];
  for (int i = start; i < end; i++) {
    out[i - start] = lines[i];
  }
  return out;
}

float[] parseImuLine(String line) {
  String[] comma = split(line, ',');
  if (comma != null && comma.length >= 8) {
    int base = comma.length - 8;
    float ts = toFloatSafe(comma[base + 0]);
    float ax = toFloatSafe(comma[base + 2]);
    float ay = toFloatSafe(comma[base + 3]);
    float az = toFloatSafe(comma[base + 4]);
    float gx = toFloatSafe(comma[base + 5]);
    float gy = toFloatSafe(comma[base + 6]);
    float gz = toFloatSafe(comma[base + 7]);
    if (!Float.isNaN(ts) && !Float.isNaN(ax) && !Float.isNaN(ay) && !Float.isNaN(az) && !Float.isNaN(gx) && !Float.isNaN(gy) && !Float.isNaN(gz)) {
      return new float[]{ts, ax, ay, az, gx, gy, gz};
    }
  }

  String[] tokens = splitTokens(line, ", \t");
  if (tokens == null || tokens.length < 7) {
    return null;
  }

  FloatList nums = new FloatList();
  for (int i = 0; i < tokens.length; i++) {
    float v = toFloatSafe(tokens[i]);
    if (!Float.isNaN(v)) nums.append(v);
  }
  if (nums.size() < 7) {
    return null;
  }

  if (nums.size() >= 8) {
    int b = nums.size() - 8;
    return new float[]{nums.get(b + 0), nums.get(b + 2), nums.get(b + 3), nums.get(b + 4), nums.get(b + 5), nums.get(b + 6), nums.get(b + 7)};
  }

  int b7 = nums.size() - 7;
  return new float[]{nums.get(b7 + 0), nums.get(b7 + 1), nums.get(b7 + 2), nums.get(b7 + 3), nums.get(b7 + 4), nums.get(b7 + 5), nums.get(b7 + 6)};
}

void rebuildSignalForChannel() {
  signal.clear();
  int n = axList.size();
  for (int i = 0; i < n; i++) {
    float ax = axList.get(i);
    float ay = ayList.get(i);
    float az = azList.get(i);
    float gx = gxList.get(i);
    float gy = gyList.get(i);
    float gz = gzList.get(i);
    signal.append(selectChannel(channelMode, ax, ay, az, gx, gy, gz));
  }
}

void estimateFs(FloatList timestamps) {
  if (!USE_ESTIMATED_FS) {
    sampleRateHz = FIXED_SAMPLE_RATE_HZ;
    return;
  }

  if (timestamps.size() < 2) return;

  float sumDt = 0;
  int n = 0;
  for (int i = 1; i < timestamps.size(); i++) {
    float dt = timestamps.get(i) - timestamps.get(i - 1);
    if (dt > 0 && dt < 1.0) {
      sumDt += dt;
      n++;
    }
  }

  if (n > 0) {
    float meanDt = sumDt / n;
    if (meanDt > 0) sampleRateHz = 1.0 / meanDt;
  }
}

float selectChannel(int mode, float ax, float ay, float az, float gx, float gy, float gz) {
  switch (mode) {
  case 0: return ax;
  case 1: return ay;
  case 2: return az;
  case 3: return gx;
  case 4: return gy;
  case 5: return gz;
  case 6: return sqrt(ax * ax + ay * ay + az * az);
  case 7: return sqrt(gx * gx + gy * gy + gz * gz);
  default: return ax;
  }
}

String channelName() {
  switch (channelMode) {
  case 0: return "AX";
  case 1: return "AY";
  case 2: return "AZ";
  case 3: return "GX";
  case 4: return "GY";
  case 5: return "GZ";
  case 6: return "AMAG";
  case 7: return "GMAG";
  default: return "AX";
  }
}

void runFftAndStats() {
  fftFreqs.clear();
  fftAmps.clear();

  for (int i = 0; i < PEAK_DISPLAY_COUNT; i++) {
    topBins[i] = -1;
    topFreqHz[i] = Float.NaN;
    topAmp[i] = Float.NaN;
    topPower[i] = Float.NaN;
  }

  FloatList source = amagList;
  int nAll = source.size();
  int n = min(FFT_POINTS, nAll);
  if (n < 16) return;

  float[] x = new float[n];
  int start = nAll - n;
  for (int i = 0; i < n; i++) {
    x[i] = source.get(start + i);
  }

  float mean = 0;
  for (int i = 0; i < n; i++) mean += x[i];
  mean /= n;

  float varianceLocal = 0;
  for (int i = 0; i < n; i++) {
    float d = x[i] - mean;
    varianceLocal += d * d;
    x[i] = d;
  }
  varianceLocal /= n;

  signalMean = mean;
  signalVar = varianceLocal;
  signalStd = sqrt(varianceLocal);

  for (int i = 0; i < n; i++) {
    float w = 0.5 * (1.0 - cos(TWO_PI * i / (n - 1)));
    x[i] *= w;
  }

  int half = n / 2;
  float sumW = 0;
  float meanFreqWeighted = 0;

  for (int k = 0; k <= half; k++) {
    float re = 0;
    float im = 0;
    for (int t = 0; t < n; t++) {
      float ph = TWO_PI * k * t / n;
      re += x[t] * cos(ph);
      im -= x[t] * sin(ph);
    }
    float amp = sqrt(re * re + im * im) / n;
    float freq = k * sampleRateHz / n;
    fftFreqs.append(freq);
    fftAmps.append(amp);

    if (k >= 1 && amp > 0) {
      sumW += amp;
      meanFreqWeighted += amp * freq;
    }

  }

  for (int rank = 0; rank < PEAK_DISPLAY_COUNT; rank++) {
    float best = -1;
    int bestK = -1;

    for (int k = 1; k <= half; k++) {
      boolean excluded = false;
      for (int prev = 0; prev < rank; prev++) {
        if (topBins[prev] > 0 && abs(k - topBins[prev]) <= PEAK_EXCLUSION_BINS) {
          excluded = true;
          break;
        }
      }
      if (excluded) {
        continue;
      }

      float amp = fftAmps.get(k);
      if (amp > best) {
        best = amp;
        bestK = k;
      }
    }

    if (bestK > 0) {
      topBins[rank] = bestK;
      topFreqHz[rank] = bestK * sampleRateHz / n;
      topAmp[rank] = best;
      topPower[rank] = best * best;
    }
  }

  if (sumW > 0) {
    specMeanFreq = meanFreqWeighted / sumW;
    float varFreq = 0;
    for (int k = 1; k <= half; k++) {
      float freq = fftFreqs.get(k);
      float amp = fftAmps.get(k);
      if (amp > 0) {
        float df = freq - specMeanFreq;
        varFreq += amp * df * df;
      }
    }
    specVarFreq = varFreq / sumW;
    specStdFreq = sqrt(specVarFreq);
  }

}

void computeSpectrumForSeries(FloatList series, FloatList outFreqs, FloatList outAmps, float[] outFreqPower) {
  outFreqs.clear();
  outAmps.clear();
  outFreqPower[0] = Float.NaN;
  outFreqPower[1] = Float.NaN;

  int nAll = series.size();
  int n = min(FFT_POINTS, nAll);
  if (n < 16) return;

  float[] x = new float[n];
  int start = nAll - n;
  for (int i = 0; i < n; i++) {
    x[i] = series.get(start + i);
  }

  float mean = 0;
  for (int i = 0; i < n; i++) mean += x[i];
  mean /= n;
  for (int i = 0; i < n; i++) {
    x[i] -= mean;
  }

  for (int i = 0; i < n; i++) {
    float w = 0.5 * (1.0 - cos(TWO_PI * i / (n - 1)));
    x[i] *= w;
  }

  int half = n / 2;
  float bestAmp = -1;
  int bestK = -1;
  for (int k = 1; k <= half; k++) {
    float re = 0;
    float im = 0;
    for (int t = 0; t < n; t++) {
      float ph = TWO_PI * k * t / n;
      re += x[t] * cos(ph);
      im -= x[t] * sin(ph);
    }
    float amp = sqrt(re * re + im * im) / n;
    float freq = k * sampleRateHz / n;
    outFreqs.append(freq);
    outAmps.append(amp);
    if (amp > bestAmp) {
      bestAmp = amp;
      bestK = k;
    }
  }

  if (bestK > 0) {
    float freq = bestK * sampleRateHz / n;
    outFreqPower[0] = freq;
    outFreqPower[1] = bestAmp * bestAmp;
  }
}

void computeSixAxisSpectra() {
  float[] out = new float[2];

  computeSpectrumForSeries(axList, axisFftFreqs[0], axisFftAmps[0], out);
  axisPeakFreqHz[0] = out[0];
  axisPeakPower[0] = out[1];

  computeSpectrumForSeries(ayList, axisFftFreqs[1], axisFftAmps[1], out);
  axisPeakFreqHz[1] = out[0];
  axisPeakPower[1] = out[1];

  computeSpectrumForSeries(azList, axisFftFreqs[2], axisFftAmps[2], out);
  axisPeakFreqHz[2] = out[0];
  axisPeakPower[2] = out[1];

  computeSpectrumForSeries(gxList, axisFftFreqs[3], axisFftAmps[3], out);
  axisPeakFreqHz[3] = out[0];
  axisPeakPower[3] = out[1];

  computeSpectrumForSeries(gyList, axisFftFreqs[4], axisFftAmps[4], out);
  axisPeakFreqHz[4] = out[0];
  axisPeakPower[4] = out[1];

  computeSpectrumForSeries(gzList, axisFftFreqs[5], axisFftAmps[5], out);
  axisPeakFreqHz[5] = out[0];
  axisPeakPower[5] = out[1];

  FloatList amagFreqs = new FloatList();
  FloatList amagAmps = new FloatList();
  computeSpectrumForSeries(amagList, amagFreqs, amagAmps, out);
  accelCombinedFreqs = amagFreqs;
  accelCombinedAmps = amagAmps;
  accelPeakFreqHz = out[0];
  accelPeakPower = out[1];
  accelTotalPower = sumSpectrumPower(amagAmps);

  FloatList gmagFreqs = new FloatList();
  FloatList gmagAmps = new FloatList();
  computeSpectrumForSeries(gmagList, gmagFreqs, gmagAmps, out);
  gyroCombinedFreqs = gmagFreqs;
  gyroCombinedAmps = gmagAmps;
  gyroPeakFreqHz = out[0];
  gyroPeakPower = out[1];
  gyroTotalPower = sumSpectrumPower(gmagAmps);

  computeTopPeaks(gyroCombinedAmps, gmagTopFreqHz, gmagTopPower);
}

void computeTopPeaks(FloatList amps, float[] outFreqHz, float[] outPower) {
  for (int i = 0; i < PEAK_DISPLAY_COUNT; i++) {
    outFreqHz[i] = Float.NaN;
    outPower[i] = Float.NaN;
  }
  if (amps == null || amps.size() <= 1) return;

  int n = (amps.size() - 1) * 2;
  if (n <= 0) return;
  int half = amps.size() - 1;
  int[] selectedBins = new int[PEAK_DISPLAY_COUNT];
  for (int i = 0; i < PEAK_DISPLAY_COUNT; i++) selectedBins[i] = -1;

  for (int rank = 0; rank < PEAK_DISPLAY_COUNT; rank++) {
    float bestAmp = -1;
    int bestK = -1;

    for (int k = 1; k <= half; k++) {
      boolean excluded = false;
      for (int prev = 0; prev < rank; prev++) {
        if (selectedBins[prev] > 0 && abs(k - selectedBins[prev]) <= PEAK_EXCLUSION_BINS) {
          excluded = true;
          break;
        }
      }
      if (excluded) continue;

      float a = amps.get(k);
      if (a > bestAmp) {
        bestAmp = a;
        bestK = k;
      }
    }

    if (bestK > 0) {
      selectedBins[rank] = bestK;
      outFreqHz[rank] = bestK * sampleRateHz / n;
      outPower[rank] = bestAmp * bestAmp;
    }
  }
}

float sumSpectrumPower(FloatList amps) {
  if (amps == null || amps.size() == 0) return Float.NaN;
  float s = 0;
  for (int i = 0; i < amps.size(); i++) {
    float a = amps.get(i);
    s += a * a;
  }
  return s;
}

String formatPowerValue(float v) {
  if (Float.isNaN(v)) return "-";
  float av = abs(v);
  if (av > 0 && av < 0.0001) {
    return String.format("%.3e", v);
  }
  return nf(v, 1, 6);
}

String axisSummaryLine(int startIdx, int endIdx) {
  String s = "";
  for (int i = startIdx; i <= endIdx; i++) {
    if (i >= 0 && i < 6) {
      s += axisNames[i] + ":";
      if (!Float.isNaN(axisPeakFreqHz[i])) {
        s += nf(axisPeakFreqHz[i], 1, 3) + "Hz(P=" + nf(axisPeakPower[i], 1, 6) + ")";
      } else {
        s += "-";
      }
      if (i < endIdx) s += "   ";
    }
  }
  return s;
}

String buildPeakSummaryLine(String prefix, float[] freqs, float[] powers) {
  String s = "";
  if (prefix != null && prefix.length() > 0) {
    s += prefix + " ";
  }
  for (int r = 1; r <= PEAK_DISPLAY_COUNT; r++) {
    int idx = r - 1;
    if (!Float.isNaN(freqs[idx])) {
      s += "P" + r + ": " + nf(freqs[idx], 1, 3) + "Hz (P=" + nf(powers[idx], 1, 6) + ")";
    } else {
      s += "P" + r + ": -";
    }
    if (r < PEAK_DISPLAY_COUNT) {
      s += "   ";
    }
  }
  return s;
}

color peakColor(int idx) {
  if (idx == 0) return color(120, 255, 120);
  if (idx == 1) return color(120, 200, 255);
  if (idx == 2) return color(255, 210, 120);
  return color(255, 160, 220);
}

float toFloatSafe(String s) {
  try {
    return Float.parseFloat(trim(s));
  }
  catch (Exception e) {
    return Float.NaN;
  }
}

void drawHeader() {
  fill(235);
  textSize(19);
  text("Spresense Raw CSV FFT Viewer", 30, 38);

  fill(180);
  textSize(13);
  String fsMode = USE_ESTIMATED_FS ? "EST" : "FIXED";
  text("channel=" + channelName() + " | fs=" + nf(sampleRateHz, 1, 3) + " Hz(" + fsMode + ") | FFT_N=" + min(FFT_POINTS, signal.size()) + " | graph=" + graphModeName(), 30, 64);

  fill(200);
  textSize(12);
  text(axisSummaryLine(0, 2), 30, 80);
  text(axisSummaryLine(3, 5), 30, 96);

  fill(230, 255, 150);
  textSize(13);
  text(buildPeakSummaryLine("AMAG", topFreqHz, topPower), 30, 114);
  text(buildPeakSummaryLine("GMAG", gmagTopFreqHz, gmagTopPower), 30, 132);

  fill(180);
  textSize(13);
  text("signal mean=" + nf(signalMean, 1, 6) + " var=" + nf(signalVar, 1, 6) + " std=" + nf(signalStd, 1, 6), 30, 152);
  text("spectrum meanFreq=" + nf(specMeanFreq, 1, 3) + " Hz  varFreq=" + nf(specVarFreq, 1, 6) + "  stdFreq=" + nf(specStdFreq, 1, 3) + " Hz", 30, 172);

  fill(130);
  text("File: " + loadedFilePath, 30, 192);
  text("Status: " + statusText + " | total=" + totalLines + " | key 1..8: selected channel text only, L: load another", 30, 210);
}

void drawSixAxisGrid(int x, int y, int w, int h) {
  int cols = 3;
  int rows = 2;
  int gapX = 12;
  int gapY = 12;

  int cellW = (w - gapX * (cols - 1)) / cols;
  int cellH = (h - gapY * (rows - 1)) / rows;

  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      int idx = r * cols + c;
      int cx = x + c * (cellW + gapX);
      int cy = y + r * (cellH + gapY);
      drawAxisSpectrumPanel(idx, cx, cy, cellW, cellH);
    }
  }
}

void drawAxisSpectrumPanel(int axisIdx, int x, int y, int w, int h) {
  stroke(85);
  noFill();
  rect(x, y, w, h);

  FloatList freqs = axisFftFreqs[axisIdx];
  FloatList amps = axisFftAmps[axisIdx];

  if (amps.size() == 0) {
    fill(190);
    textSize(12);
    text(axisNames[axisIdx] + " : no data", x + 10, y + 20);
    return;
  }

  float nyq = sampleRateHz * 0.5;
  float maxAmp = 1e-9;
  float maxPower = 1e-9;
  for (int i = 0; i < amps.size(); i++) {
    float a = amps.get(i);
    maxAmp = max(maxAmp, a);
    maxPower = max(maxPower, a * a);
  }

  noStroke();
  if (GRAPH_MODE == GRAPH_MODE_POWER || GRAPH_MODE == GRAPH_MODE_BOTH) {
    fill(120, 190, 255);
    for (int i = 0; i < amps.size(); i++) {
      float f = freqs.get(i);
      float a = amps.get(i);
      float p = a * a;
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float ph = map(p, 0, maxPower, 0, h - 26);
      rect(px, y + h - ph - 2, max(1, w / (float)amps.size()), ph);
    }
  }

  if (GRAPH_MODE == GRAPH_MODE_AMPLITUDE) {
    fill(255, 170, 85);
    for (int i = 0; i < amps.size(); i++) {
      float f = freqs.get(i);
      float a = amps.get(i);
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float ph = map(a, 0, maxAmp, 0, h - 26);
      rect(px, y + h - ph - 2, max(1, w / (float)amps.size()), ph);
    }
  } else if (GRAPH_MODE == GRAPH_MODE_BOTH) {
    stroke(255, 190, 120);
    noFill();
    beginShape();
    for (int i = 0; i < amps.size(); i++) {
      float f = freqs.get(i);
      float a = amps.get(i);
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float py = map(a, 0, maxAmp, y + h - 2, y + 8);
      vertex(px, py);
    }
    endShape();
    noStroke();
  }

  drawPeakMarker(axisPeakFreqHz[axisIdx], x, y, w, h, nyq, peakColor(axisIdx % PEAK_DISPLAY_COUNT));

  fill(210);
  textSize(12);
  text(axisNames[axisIdx] + "  peak=" + nf(axisPeakFreqHz[axisIdx], 1, 3) + "Hz", x + 8, y + 16);

  fill(160);
  textSize(10);
  String modeText = (GRAPH_MODE == GRAPH_MODE_POWER) ? "Power" : ((GRAPH_MODE == GRAPH_MODE_BOTH) ? "Power + Amp" : "Amp");
  text(modeText, x + 8, y + 30);
  text("0", x + 2, y + h + 12);
  text(nf(nyq, 1, 1) + "Hz", x + w - 38, y + h + 12);
}

void drawSpectrum(int x, int y, int w, int h) {
  stroke(85);
  noFill();
  rect(x, y, w, h);

  if (fftAmps.size() == 0) {
    fill(190);
    text("No valid raw samples found", x + 10, y + 22);
    return;
  }

  float nyq = sampleRateHz * 0.5;
  float maxAmp = 1e-9;
  for (int i = 0; i < fftAmps.size(); i++) maxAmp = max(maxAmp, fftAmps.get(i));

  noStroke();
  fill(255, 170, 85);
  for (int i = 0; i < fftAmps.size(); i++) {
    float f = fftFreqs.get(i);
    float a = fftAmps.get(i);
    float px = map(f, 0, nyq, x + 2, x + w - 2);
    float ph = map(a, 0, maxAmp, 0, h - 24);
    rect(px, y + h - ph - 2, max(1, w / (float)fftAmps.size()), ph);
  }

  for (int i = 0; i < PEAK_DISPLAY_COUNT; i++) {
    drawPeakMarker(topFreqHz[i], x, y, w, h, nyq, peakColor(i));
  }
  drawFreqAxis(x, y, w, h, nyq);
  drawValueAxis(x, y, w, h, maxAmp, "Amp");

  fill(190);
  text("Amplitude Spectrum", x + 10, y + 20);
}

void drawPower(int x, int y, int w, int h) {
  stroke(85);
  noFill();
  rect(x, y, w, h);

  if (fftAmps.size() == 0) {
    fill(190);
    text("No valid raw samples found", x + 10, y + 22);
    return;
  }

  float nyq = sampleRateHz * 0.5;
  float maxPower = 1e-9;
  for (int i = 0; i < fftAmps.size(); i++) {
    float p = fftAmps.get(i) * fftAmps.get(i);
    maxPower = max(maxPower, p);
  }

  stroke(90, 170, 255);
  noFill();
  beginShape();
  for (int i = 0; i < fftAmps.size(); i++) {
    float f = fftFreqs.get(i);
    float p = fftAmps.get(i) * fftAmps.get(i);
    float px = map(f, 0, nyq, x + 2, x + w - 2);
    float py = map(p, 0, maxPower, y + h - 2, y + 8);
    vertex(px, py);
  }
  endShape();

  for (int i = 0; i < PEAK_DISPLAY_COUNT; i++) {
    drawPeakMarker(topFreqHz[i], x, y, w, h, nyq, peakColor(i));
  }
  drawFreqAxis(x, y, w, h, nyq);
  drawValueAxis(x, y, w, h, maxPower, "Power");

  fill(190);
  text("Power Spectrum (amp^2)", x + 10, y + 20);
}

void drawFreqAxis(int x, int y, int w, int h, float nyq) {
  if (nyq <= 0) return;

  int ticks = 6;
  stroke(100);
  fill(170);
  textSize(11);

  for (int i = 0; i <= ticks; i++) {
    float f = nyq * i / ticks;
    float px = map(f, 0, nyq, x + 2, x + w - 2);

    line(px, y + h - 2, px, y + h + 4);
    text(nf(f, 1, 1), px - 12, y + h + 18);
  }

  text("Frequency [Hz]", x + w - 95, y + h + 18);
}

void drawValueAxis(int x, int y, int w, int h, float maxValue, String label) {
  if (maxValue <= 0) return;

  int ticks = 5;
  stroke(100);
  fill(170);
  textSize(11);

  for (int i = 0; i <= ticks; i++) {
    float v = maxValue * i / ticks;
    float py = map(v, 0, maxValue, y + h - 2, y + 8);

    line(x - 4, py, x + 2, py);
    text(nf(v, 1, 4), x - 70, py + 4);
  }

  text(label, x - 40, y + 14);
}

void drawPeakMarker(float freq, int x, int y, int w, int h, float nyq, color c) {
  if (Float.isNaN(freq) || nyq <= 0) return;
  float px = map(freq, 0, nyq, x + 2, x + w - 2);
  stroke(red(c), green(c), blue(c), 70);
  strokeWeight(1);
  line(px, y + 2, px, y + h - 2);
}

void drawCombinedAccelSpectrum(int x, int y, int w, int h) {
  stroke(85);
  noFill();
  rect(x, y, w, h);

  if (accelCombinedAmps.size() == 0) {
    fill(190);
    textSize(12);
    text("AMAG combined spectrum: no data", x + 10, y + 20);
    return;
  }

  float nyq = sampleRateHz * 0.5;
  float maxAmp = 1e-9;
  float maxPower = 1e-9;
  for (int i = 0; i < accelCombinedAmps.size(); i++) {
    float a = accelCombinedAmps.get(i);
    maxAmp = max(maxAmp, a);
    maxPower = max(maxPower, a * a);
  }

  noStroke();
  if (GRAPH_MODE == GRAPH_MODE_POWER || GRAPH_MODE == GRAPH_MODE_BOTH) {
    fill(120, 220, 140);
    for (int i = 0; i < accelCombinedAmps.size(); i++) {
      float f = accelCombinedFreqs.get(i);
      float a = accelCombinedAmps.get(i);
      float p = a * a;
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float ph = map(p, 0, maxPower, 0, h - 26);
      rect(px, y + h - ph - 2, max(1, w / (float)accelCombinedAmps.size()), ph);
    }
  }

  if (GRAPH_MODE == GRAPH_MODE_AMPLITUDE) {
    fill(255, 170, 85);
    for (int i = 0; i < accelCombinedAmps.size(); i++) {
      float f = accelCombinedFreqs.get(i);
      float a = accelCombinedAmps.get(i);
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float ph = map(a, 0, maxAmp, 0, h - 26);
      rect(px, y + h - ph - 2, max(1, w / (float)accelCombinedAmps.size()), ph);
    }
  } else if (GRAPH_MODE == GRAPH_MODE_BOTH) {
    stroke(255, 190, 120);
    noFill();
    beginShape();
    for (int i = 0; i < accelCombinedAmps.size(); i++) {
      float f = accelCombinedFreqs.get(i);
      float a = accelCombinedAmps.get(i);
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float py = map(a, 0, maxAmp, y + h - 2, y + 8);
      vertex(px, py);
    }
    endShape();
    noStroke();
  }

  drawPeakMarker(accelPeakFreqHz, x, y, w, h, nyq, color(160, 255, 160));

  fill(210);
  textSize(12);
  text("AMAG combined  peak=" + nf(accelPeakFreqHz, 1, 3) + "Hz  totalP=" + formatPowerValue(accelTotalPower), x + 8, y + 16);

  fill(160);
  textSize(10);
  String modeText = (GRAPH_MODE == GRAPH_MODE_POWER) ? "Power" : ((GRAPH_MODE == GRAPH_MODE_BOTH) ? "Power + Amp" : "Amp");
  text(modeText, x + 8, y + 30);
  text("0", x + 2, y + h + 12);
  text(nf(nyq, 1, 1) + "Hz", x + w - 44, y + h + 12);
}

void drawCombinedGyroSpectrum(int x, int y, int w, int h) {
  stroke(85);
  noFill();
  rect(x, y, w, h);

  if (gyroCombinedAmps.size() == 0) {
    fill(190);
    textSize(12);
    text("GMAG combined spectrum: no data", x + 10, y + 20);
    return;
  }

  float nyq = sampleRateHz * 0.5;
  float maxAmp = 1e-9;
  float maxPower = 1e-9;
  for (int i = 0; i < gyroCombinedAmps.size(); i++) {
    float a = gyroCombinedAmps.get(i);
    maxAmp = max(maxAmp, a);
    maxPower = max(maxPower, a * a);
  }

  noStroke();
  if (GRAPH_MODE == GRAPH_MODE_POWER || GRAPH_MODE == GRAPH_MODE_BOTH) {
    fill(130, 180, 255);
    for (int i = 0; i < gyroCombinedAmps.size(); i++) {
      float f = gyroCombinedFreqs.get(i);
      float a = gyroCombinedAmps.get(i);
      float p = a * a;
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float ph = map(p, 0, maxPower, 0, h - 26);
      rect(px, y + h - ph - 2, max(1, w / (float)gyroCombinedAmps.size()), ph);
    }
  }

  if (GRAPH_MODE == GRAPH_MODE_AMPLITUDE) {
    fill(255, 170, 85);
    for (int i = 0; i < gyroCombinedAmps.size(); i++) {
      float f = gyroCombinedFreqs.get(i);
      float a = gyroCombinedAmps.get(i);
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float ph = map(a, 0, maxAmp, 0, h - 26);
      rect(px, y + h - ph - 2, max(1, w / (float)gyroCombinedAmps.size()), ph);
    }
  } else if (GRAPH_MODE == GRAPH_MODE_BOTH) {
    stroke(255, 190, 120);
    noFill();
    beginShape();
    for (int i = 0; i < gyroCombinedAmps.size(); i++) {
      float f = gyroCombinedFreqs.get(i);
      float a = gyroCombinedAmps.get(i);
      float px = map(f, 0, nyq, x + 2, x + w - 2);
      float py = map(a, 0, maxAmp, y + h - 2, y + 8);
      vertex(px, py);
    }
    endShape();
    noStroke();
  }

  drawPeakMarker(gyroPeakFreqHz, x, y, w, h, nyq, color(160, 210, 255));

  fill(210);
  textSize(12);
  text("GMAG combined  peak=" + nf(gyroPeakFreqHz, 1, 3) + "Hz  totalP=" + formatPowerValue(gyroTotalPower), x + 8, y + 16);

  fill(160);
  textSize(10);
  String modeText = (GRAPH_MODE == GRAPH_MODE_POWER) ? "Power" : ((GRAPH_MODE == GRAPH_MODE_BOTH) ? "Power + Amp" : "Amp");
  text(modeText, x + 8, y + 30);
  text("0", x + 2, y + h + 12);
  text(nf(nyq, 1, 1) + "Hz", x + w - 44, y + h + 12);
}

void drawFooterPower(int x, int y, int w, int h) {
  noStroke();
  fill(26);
  rect(x, y, w, h);

  fill(220);
  textSize(13);

  String accText = "Accel power: -";
  if (!Float.isNaN(accelTotalPower)) {
    accText = "Accel power: " + formatPowerValue(accelTotalPower) + " (peak " + nf(accelPeakFreqHz, 1, 3) + "Hz, P=" + formatPowerValue(accelPeakPower) + ")";
  }

  String gyrText = "Gyro power: -";
  if (!Float.isNaN(gyroTotalPower)) {
    gyrText = "Gyro power: " + formatPowerValue(gyroTotalPower) + " (peak " + nf(gyroPeakFreqHz, 1, 3) + "Hz, P=" + formatPowerValue(gyroPeakPower) + ")";
  }

  text(accText + "   |   " + gyrText, x + 8, y + h - 14);
}

void keyPressed() {
  if (key >= '1' && key <= '8') {
    channelMode = (int)(key - '1');
    rebuildSignalForChannel();
    runFftAndStats();
  } else if (key == 'l' || key == 'L') {
    selectInput("Select raw CSV log file", "fileSelected");
  }
}
