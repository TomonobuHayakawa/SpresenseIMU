// ============================================
// Spresense IMU DC Visualizer (Processing)
// Input line format:
//   timestamp,temp,ax,ay,az,gx,gy,gz
// Optional calibration lines:
//   gyro_bias,bx,by,bz
//   gravity_mag,g
// ============================================

final int FOOTER_HEIGHT = 50;
final int COMBINED_PANEL_HEIGHT = 120;
final int PANEL_GAP = 10;

String loadedFilePath = "(not loaded)";
String statusText = "Press L to load raw CSV log file";

int totalLines = 0;
int parsedLines = 0;
int skippedLines = 0;

FloatList timestamps = new FloatList();
FloatList axList = new FloatList();
FloatList ayList = new FloatList();
FloatList azList = new FloatList();
FloatList gxList = new FloatList();
FloatList gyList = new FloatList();
FloatList gzList = new FloatList();

FloatList gxCorrList = new FloatList();
FloatList gyCorrList = new FloatList();
FloatList gzCorrList = new FloatList();
FloatList accelCompositeList = new FloatList(); // |a| - trueGravity
FloatList gyroCompositeList = new FloatList();  // |g_corr|

float gyroBiasX = 0.0;
float gyroBiasY = 0.0;
float gyroBiasZ = 0.0;
float trueGravity = 1.0;

boolean hasBiasFromLog = false;
boolean hasGravityFromLog = false;

void setup() {
  size(1200, 760);
  frameRate(60);
  textFont(createFont("Consolas", 13));
  selectInput("Select raw CSV log file", "fileSelected");
}

void draw() {
  background(18);
  drawHeader();

  int contentX = 20;
  int contentW = width - 40;

  int gridY = 225;
  int gridH = height - gridY - FOOTER_HEIGHT - (COMBINED_PANEL_HEIGHT * 2) - (PANEL_GAP * 2) - 12;
  if (gridH < 130) gridH = 130;

  drawSixAxisGrid(contentX, gridY, contentW, gridH);

  int combinedY = gridY + gridH + PANEL_GAP;
  drawSeriesPanel("ACC_COMPOSITE = |a| - gravity_mag", accelCompositeList, contentX, combinedY, contentW, COMBINED_PANEL_HEIGHT, color(90, 205, 255));
  drawSeriesPanel("GYRO_COMPOSITE = |g_corr|", gyroCompositeList, contentX, combinedY + COMBINED_PANEL_HEIGHT + PANEL_GAP, contentW, COMBINED_PANEL_HEIGHT, color(255, 180, 85));

  drawFooter();
}

void keyPressed() {
  if (key == 'l' || key == 'L') {
    selectInput("Select raw CSV log file", "fileSelected");
  }
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
  skippedLines = 0;

  timestamps.clear();
  axList.clear();
  ayList.clear();
  azList.clear();
  gxList.clear();
  gyList.clear();
  gzList.clear();

  gxCorrList.clear();
  gyCorrList.clear();
  gzCorrList.clear();
  accelCompositeList.clear();
  gyroCompositeList.clear();

  gyroBiasX = 0.0;
  gyroBiasY = 0.0;
  gyroBiasZ = 0.0;
  trueGravity = 1.0;

  hasBiasFromLog = false;
  hasGravityFromLog = false;
}

void loadRawLog(String path) {
  String[] lines = loadStrings(path);
  if (lines == null) {
    statusText = "Failed to load file";
    return;
  }

  loadedFilePath = path;
  resetData();

  // Parse calibration lines from the full file first.
  for (int i = 0; i < lines.length; i++) {
    String line = trim(lines[i]);
    if (line.length() == 0) continue;
    parseCalibrationLine(line);
  }

  // Then trim header/footer and parse only payload lines.
  String[] payload = extractPayloadLines(lines);

  for (int i = 0; i < payload.length; i++) {
    String line = trim(payload[i]);
    if (line.length() == 0) {
      continue;
    }

    if (isSkipLine(line)) {
      continue;
    }

    totalLines++;

    float[] parsed = parseImuLine(line);
    if (parsed == null) {
      skippedLines++;
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
      skippedLines++;
      continue;
    }

    timestamps.append(ts);
    axList.append(ax);
    ayList.append(ay);
    azList.append(az);
    gxList.append(gx);
    gyList.append(gy);
    gzList.append(gz);
    parsedLines++;
  }

  if (!hasBiasFromLog) {
    estimateGyroBiasFromHead(200);
  }
  if (!hasGravityFromLog) {
    estimateTrueGravityFromHead(200);
  }

  rebuildDerivedSeries();

  String biasSource = hasBiasFromLog ? "log" : "estimated";
  String gravitySource = hasGravityFromLog ? "log" : "estimated";
  statusText = "Loaded: samples=" + parsedLines + ", skipped=" + skippedLines + " | bias=" + biasSource + ", gravity=" + gravitySource;
}

String[] extractPayloadLines(String[] lines) {
  if (lines == null || lines.length == 0) {
    return new String[0];
  }

  int start = 0;
  int end = lines.length;

  // Prefer explicit dump section.
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

  // Remove CSV header if present in payload.
  for (int i = start; i < end; i++) {
    String line = trim(lines[i]).toLowerCase();
    if (line.startsWith("timestamp,temp,ax,ay,az,gx,gy,gz")) {
      start = i + 1;
      break;
    }
  }

  if (start < 0) start = 0;
  if (end > lines.length) end = lines.length;
  if (start >= end) {
    return new String[0];
  }

  String[] out = new String[end - start];
  for (int i = start; i < end; i++) {
    out[i - start] = lines[i];
  }
  return out;
}

boolean parseCalibrationLine(String line) {
  if (line.startsWith("gyro_bias,")) {
    String[] t = split(line, ',');
    if (t != null && t.length >= 4) {
      float bx = toFloatSafe(t[1]);
      float by = toFloatSafe(t[2]);
      float bz = toFloatSafe(t[3]);
      if (!Float.isNaN(bx) && !Float.isNaN(by) && !Float.isNaN(bz)) {
        gyroBiasX = bx;
        gyroBiasY = by;
        gyroBiasZ = bz;
        hasBiasFromLog = true;
        return true;
      }
    }
  }

  if (line.startsWith("gravity_mag,")) {
    String[] t = split(line, ',');
    if (t != null && t.length >= 2) {
      float g = toFloatSafe(t[1]);
      if (!Float.isNaN(g) && g > 0.0) {
        trueGravity = g;
        hasGravityFromLog = true;
        return true;
      }
    }
  }

  return false;
}

boolean isSkipLine(String line) {
  if (line.startsWith("===") || line.startsWith("Capture") || line.startsWith("Start") || line.startsWith("Dump") || line.startsWith("[")) {
    return true;
  }
  return false;
}

float[] parseImuLine(String line) {
  String[] comma = split(line, ',');
  if (comma != null && comma.length >= 8) {
    int b = comma.length - 8;
    float ts = toFloatSafe(comma[b + 0]);
    float ax = toFloatSafe(comma[b + 2]);
    float ay = toFloatSafe(comma[b + 3]);
    float az = toFloatSafe(comma[b + 4]);
    float gx = toFloatSafe(comma[b + 5]);
    float gy = toFloatSafe(comma[b + 6]);
    float gz = toFloatSafe(comma[b + 7]);
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
    int b8 = nums.size() - 8;
    return new float[]{nums.get(b8 + 0), nums.get(b8 + 2), nums.get(b8 + 3), nums.get(b8 + 4), nums.get(b8 + 5), nums.get(b8 + 6), nums.get(b8 + 7)};
  }

  int b7 = nums.size() - 7;
  return new float[]{nums.get(b7 + 0), nums.get(b7 + 1), nums.get(b7 + 2), nums.get(b7 + 3), nums.get(b7 + 4), nums.get(b7 + 5), nums.get(b7 + 6)};
}

void estimateGyroBiasFromHead(int headCount) {
  int n = min(headCount, gxList.size());
  if (n <= 0) return;

  float sx = 0.0;
  float sy = 0.0;
  float sz = 0.0;
  for (int i = 0; i < n; i++) {
    sx += gxList.get(i);
    sy += gyList.get(i);
    sz += gzList.get(i);
  }

  gyroBiasX = sx / n;
  gyroBiasY = sy / n;
  gyroBiasZ = sz / n;
}

void estimateTrueGravityFromHead(int headCount) {
  int n = min(headCount, axList.size());
  if (n <= 0) return;

  float sum = 0.0;
  for (int i = 0; i < n; i++) {
    float ax = axList.get(i);
    float ay = ayList.get(i);
    float az = azList.get(i);
    sum += sqrt(ax * ax + ay * ay + az * az);
  }

  trueGravity = sum / n;
}

void rebuildDerivedSeries() {
  gxCorrList.clear();
  gyCorrList.clear();
  gzCorrList.clear();
  accelCompositeList.clear();
  gyroCompositeList.clear();

  int n = axList.size();
  for (int i = 0; i < n; i++) {
    float ax = axList.get(i);
    float ay = ayList.get(i);
    float az = azList.get(i);
    float gx = gxList.get(i);
    float gy = gyList.get(i);
    float gz = gzList.get(i);

    float gxCorr = gx - gyroBiasX;
    float gyCorr = gy - gyroBiasY;
    float gzCorr = gz - gyroBiasZ;

    float amag = sqrt(ax * ax + ay * ay + az * az);
    float accelComposite = amag - trueGravity;
    float gyroComposite = sqrt(gxCorr * gxCorr + gyCorr * gyCorr + gzCorr * gzCorr);

    gxCorrList.append(gxCorr);
    gyCorrList.append(gyCorr);
    gzCorrList.append(gzCorr);
    accelCompositeList.append(accelComposite);
    gyroCompositeList.append(gyroComposite);
  }
}

float toFloatSafe(String s) {
  if (s == null) return Float.NaN;
  s = trim(s);
  if (s.length() == 0) return Float.NaN;
  try {
    return Float.parseFloat(s);
  }
  catch (Exception e) {
    return Float.NaN;
  }
}

void drawHeader() {
  float axMax = maxOfList(axList);
  float ayMax = maxOfList(ayList);
  float azMax = maxOfList(azList);
  float gxMax = maxOfList(gxCorrList);
  float gyMax = maxOfList(gyCorrList);
  float gzMax = maxOfList(gzCorrList);
  float accCompMax = maxOfList(accelCompositeList);
  float gyroCompMax = maxOfList(gyroCompositeList);

  fill(235);
  textSize(18);
  text("Spresense IMU DC Visualizer", 20, 32);

  textSize(12);
  fill(185);
  text("File: " + loadedFilePath, 20, 56);
  text("Samples: " + parsedLines + "  (total lines: " + totalLines + ", skipped: " + skippedLines + ")", 20, 74);
  text("gyro_bias = [" + nf(gyroBiasX, 1, 5) + ", " + nf(gyroBiasY, 1, 5) + ", " + nf(gyroBiasZ, 1, 5) + "]", 20, 92);
  text("gravity_mag = " + nf(trueGravity, 1, 5), 20, 110);

  textSize(15);
  fill(210);
  text("MAX  ACC:  AX=" + fmtVal(axMax) + "  AY=" + fmtVal(ayMax) + "  AZ=" + fmtVal(azMax), 20, 134);
  text("MAX  GYRO: GX=" + fmtVal(gxMax) + "  GY=" + fmtVal(gyMax) + "  GZ=" + fmtVal(gzMax), 20, 156);
  text("MAX  COMP: ACC_C=" + fmtVal(accCompMax) + "  GYRO_C=" + fmtVal(gyroCompMax), 20, 178);

  textSize(12);
  fill(145);
  text(statusText, 20, 202);
}

float maxOfList(FloatList list) {
  if (list == null || list.size() == 0) {
    return Float.NaN;
  }

  float maxV = Float.NEGATIVE_INFINITY;
  for (int i = 0; i < list.size(); i++) {
    float v = list.get(i);
    if (v > maxV) {
      maxV = v;
    }
  }
  return maxV;
}

String fmtVal(float v) {
  if (!isFinite(v)) {
    return "N/A";
  }
  return nf(v, 1, 5);
}

void drawSixAxisGrid(int x, int y, int w, int h) {
  int colGap = 10;
  int rowGap = 10;
  int panelW = (w - (colGap * 2)) / 3;
  int panelH = (h - rowGap) / 2;

  float[] accRange = calcGlobalRange3(axList, ayList, azList);
  float[] gyroRange = calcGlobalRange3(gxCorrList, gyCorrList, gzCorrList);

  drawSeriesPanel("AX (raw)", axList, x, y, panelW, panelH, color(90, 205, 255), accRange[0], accRange[1]);
  drawSeriesPanel("AY (raw)", ayList, x + panelW + colGap, y, panelW, panelH, color(120, 220, 120), accRange[0], accRange[1]);
  drawSeriesPanel("AZ (raw)", azList, x + (panelW + colGap) * 2, y, panelW, panelH, color(255, 130, 130), accRange[0], accRange[1]);

  int y2 = y + panelH + rowGap;
  drawSeriesPanel("GX (bias-corrected)", gxCorrList, x, y2, panelW, panelH, color(90, 205, 255), gyroRange[0], gyroRange[1]);
  drawSeriesPanel("GY (bias-corrected)", gyCorrList, x + panelW + colGap, y2, panelW, panelH, color(120, 220, 120), gyroRange[0], gyroRange[1]);
  drawSeriesPanel("GZ (bias-corrected)", gzCorrList, x + (panelW + colGap) * 2, y2, panelW, panelH, color(255, 130, 130), gyroRange[0], gyroRange[1]);
}

float[] calcGlobalRange3(FloatList a, FloatList b, FloatList c) {
  float minV = Float.POSITIVE_INFINITY;
  float maxV = Float.NEGATIVE_INFINITY;

  for (int i = 0; i < a.size(); i++) {
    float v = a.get(i);
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }
  for (int i = 0; i < b.size(); i++) {
    float v = b.get(i);
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }
  for (int i = 0; i < c.size(); i++) {
    float v = c.get(i);
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }

  if (!isFinite(minV) || !isFinite(maxV)) {
    return new float[]{-1.0, 1.0};
  }

  return expandRange(minV, maxV);
}

void drawSeriesPanel(String title, FloatList list, int x, int y, int w, int h, int lineCol) {
  float[] r = calcRange(list);
  drawSeriesPanel(title, list, x, y, w, h, lineCol, r[0], r[1]);
}

void drawSeriesPanel(String title, FloatList list, int x, int y, int w, int h, int lineCol, float yMin, float yMax) {
  noFill();
  stroke(88);
  rect(x, y, w, h);

  stroke(42);
  for (int i = 1; i < 5; i++) {
    int gy = y + i * h / 5;
    line(x, gy, x + w, gy);
  }

  if (list.size() <= 1) {
    fill(180);
    textSize(12);
    text(title + " (no data)", x + 8, y + 18);
    return;
  }

  if (yMin < 0 && yMax > 0) {
    float zeroY = map(0, yMin, yMax, y + h - 4, y + 4);
    stroke(120, 120, 120);
    line(x + 1, zeroY, x + w - 1, zeroY);
  }

  stroke(lineCol);
  noFill();
  beginShape();
  int n = list.size();
  for (int i = 0; i < n; i++) {
    float v = list.get(i);
    float px = map(i, 0, n - 1, x + 2, x + w - 2);
    float py = map(v, yMin, yMax, y + h - 4, y + 4);
    vertex(px, py);
  }
  endShape();

  fill(205);
  textSize(12);
  float latest = list.get(n - 1);
  text(title + "  latest=" + nf(latest, 1, 5), x + 8, y + 18);
  fill(155);
  text("min=" + nf(yMin, 1, 5) + "  max=" + nf(yMax, 1, 5), x + 8, y + h - 8);
}

float[] calcRange(FloatList list) {
  if (list.size() == 0) return new float[]{-1.0, 1.0};

  float minV = Float.POSITIVE_INFINITY;
  float maxV = Float.NEGATIVE_INFINITY;

  for (int i = 0; i < list.size(); i++) {
    float v = list.get(i);
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }

  return expandRange(minV, maxV);
}

float[] expandRange(float minV, float maxV) {
  if (!isFinite(minV) || !isFinite(maxV)) {
    return new float[]{-1.0, 1.0};
  }

  if (abs(maxV - minV) < 1e-9) {
    float p = max(0.01, abs(maxV) * 0.1);
    return new float[]{minV - p, maxV + p};
  }

  float pad = (maxV - minV) * 0.08;
  return new float[]{minV - pad, maxV + pad};
}

boolean isFinite(float v) {
  return !Float.isNaN(v) && !Float.isInfinite(v);
}

void drawFooter() {
  fill(128);
  textSize(12);
  text("Keys: [L] Load log file", 20, height - 18);
}
