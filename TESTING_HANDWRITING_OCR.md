# 🧪 Testing Guide: Handwriting OCR Scanner

## How to Test the Enhanced Handwriting Recognition

### Setup
1. ✅ App should be running on your device
2. ✅ Login as a nurse
3. ✅ Navigate to **Medication Management**
4. ✅ Look for the 📷 camera button

---

## Test Scenarios

### ✅ Test 1: Clear Handwritten Prescription

**What to test:**
Write on paper with clear handwriting:
```
Rx: Metformin
Dose: 500mg
Frequency: Twice daily
Duration: 30 days
```

**Expected Results:**
- ✅ Medication: `Metformin`
- ✅ Dosage: `500mg`
- ✅ Frequency: `Twice daily`
- ✅ Duration: `30 days`
- ✅ AI Confidence: 75-90% (green badge)

---

### ✅ Test 2: Messy Handwriting with OCR Errors

**What to test:**
Write messily to simulate common OCR errors:
```
Rx: Arnoxicillin  (A looks like R)
Dose: 5 0 0 rn g  (spacing, rn→m error)
Frequency: BID
```

**Expected Results:**
- ✅ Medication: `Amoxicillin` (fuzzy matched from "Arnoxicillin")
- ✅ Dosage: `500mg` (normalized spacing and rn→m)
- ✅ Frequency: `Twice daily` (BID interpreted)
- ✅ AI Confidence: 60-80% (green/orange badge)
- ✅ Console shows: `Fuzzy match: "Arnoxicillin" → "amoxicillin"`

---

### ✅ Test 3: Numbers with Letter Confusion

**What to test:**
Write with confusing numbers/letters:
```
Ibuprofen 4O0mg  (O instead of 0)
Take l tablet    (lowercase L instead of 1)
```

**Expected Results:**
- ✅ Medication: `Ibuprofen`
- ✅ Dosage: `400mg` (O→0 corrected)
- ✅ AI should handle the confusion

---

### ✅ Test 4: Mixed Case and Spacing

**What to test:**
```
metFORMin  1 0 0 0 M G
TWICE DAILY
```

**Expected Results:**
- ✅ Medication: `Metformin` (case normalized)
- ✅ Dosage: `1000mg` (spacing normalized)
- ✅ Frequency: `Twice daily`

---

### ✅ Test 5: Common Medications

Test these handwritten medications:

| Write (with errors) | Should Recognize |
|-------------------|------------------|
| Arnoxicillin | Amoxicillin |
| Ibuproffen | Ibuprofen |
| Metforrrin | Metformin |
| Losartam | Losartan |
| Lisinopril | Lisinopril |
| Atorvastatin | Atorvastatin |
| Omeprazole | Omeprazole |

---

### ✅ Test 6: Label Detection Variations

**What to test:**
Try different label formats:
```
RX: Aspirin
Rx: Aspirin
rx: Aspirin
R.X.: Aspirin
Medication: Aspirin
Drug: Aspirin
Med: Aspirin
```

**Expected Results:**
- ✅ All should detect "Aspirin" as the medication
- ✅ High confidence (90%+)

---

### ✅ Test 7: Dosage Format Variations

**What to test:**
```
5 0 0 m g
500 mg
500mg
500MG
5OOmg (O instead of 0)
```

**Expected Results:**
- ✅ All should normalize to `500mg`

---

### ✅ Test 8: Frequency Abbreviations

**What to test:**
```
BID
bid
B.I.D.
Twice daily
2x daily
TID
QID
Once daily
QD
```

**Expected Results:**
- ✅ BID → `Twice daily`
- ✅ TID → `Three times daily`
- ✅ QID → `Four times daily`
- ✅ QD → `Once daily`

---

## Console Logging

### What to Look For:

When you scan, check VS Code terminal for:

```
=== AI Prescription Scanner (Handwriting Mode) ===
Raw text length: XXX characters
Text blocks: X
Has medical context: true

Fuzzy match: "Arnoxicillin" → "amoxicillin" (distance: 1)
Top medication candidates:
  Amoxicillin - 0.85 (fuzzy_database_match)
  
Top dosage candidates:
  500mg - 0.90 (spatial_proximity)
  
Extracted medication: Amoxicillin
Extracted dosage: 500mg
Extracted frequency: Twice daily
Extracted duration: 30 days
================================
AI Extraction Confidence: 82%
```

---

## Confidence Badge Testing

### Green Badge (70%+)
- Clear handwriting
- Known medications
- Standard formats
- Label-based detection

### Orange Badge (40-69%)
- Messy handwriting
- Some OCR errors
- Unclear spacing
- Fuzzy matches needed

### Red Badge (<40%)
- Very messy/illegible
- Unknown medications
- Heavy damage/smudging
- Non-standard formats

---

## Tips for Best Results

### ✅ DO:
1. Write on white/light paper
2. Use dark ink (black or blue)
3. Write clearly and large
4. Use standard abbreviations (BID, TID, etc.)
5. Include labels (Rx:, Dose:, etc.)
6. Ensure good lighting when taking photo
7. Hold camera steady
8. Take photo straight on (not at angle)

### ❌ DON'T:
1. Use faded/light ink
2. Write on colored/patterned paper
3. Write too small
4. Smudge the writing
5. Take blurry photos
6. Take photos in dim lighting
7. Take photos at extreme angles

---

## Troubleshooting

### Problem: "No medication detected"
**Solutions:**
- Write medication name larger
- Add a label: "Rx:" or "Medication:"
- Ensure name is at top of prescription
- Check spelling against known medications
- Try writing in CAPITAL LETTERS

### Problem: "Wrong medication detected"
**Solutions:**
- Write more clearly
- Use proper spelling
- Add context (dosage helps confirm)
- Manually edit in the dialog

### Problem: "Dosage not detected"
**Solutions:**
- Write dosage close to medication name
- Use clear numbers
- Include unit (mg, ml, etc.)
- Add label: "Dose:" or "Dosage:"

### Problem: "Low confidence (<40%)"
**Solutions:**
- Retake photo with better lighting
- Write more clearly
- Add more context (labels, units)
- Review and manually edit

---

## Real-World Test

### Create a Complete Prescription:

```
────────────────────────────
    PRESCRIPTION
────────────────────────────

Patient: Test Patient
Date: 11/19/2025

Rx: Metformin
Dosage: 500mg
Frequency: Twice daily (BID)
Duration: 30 days

Take with meals

Dr. Signature
────────────────────────────
```

**Scan this and verify:**
1. ✅ Medication name extracted
2. ✅ Dosage with unit extracted
3. ✅ Frequency interpreted correctly
4. ✅ Duration captured
5. ✅ Confidence score displayed
6. ✅ Times suggested (9AM, 9PM for BID)

---

## Success Criteria

### ✅ PASS if:
- Extracts correct medication name (or close fuzzy match)
- Parses dosage with unit
- Interprets frequency correctly
- Shows confidence badge
- Allows manual editing
- Console logs show fuzzy matching working
- Handles 1-3 character OCR errors

### ❌ FAIL if:
- Cannot extract any medication name
- Dosages completely wrong
- App crashes on scan
- No confidence badge shown
- Cannot handle any OCR errors

---

## Performance Metrics

### Target Metrics:
- **Clear handwriting:** 70-90% accuracy
- **Messy handwriting:** 50-70% accuracy  
- **Processing time:** 2-5 seconds
- **Fuzzy match success:** 80%+ for 1-2 char errors

---

## Report Issues

If you find issues, note:
1. What you wrote
2. What was extracted
3. Confidence score shown
4. Console logs
5. Photo quality
6. Lighting conditions

---

**Ready to Test? 🚀**

1. Open the app
2. Go to Medication Management
3. Click camera button 📷
4. Write a prescription
5. Scan and check results!
