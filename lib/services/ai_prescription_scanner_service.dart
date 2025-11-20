import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// AI-Powered Prescription Scanner Service
/// Uses Google ML Kit with intelligent parsing algorithms to extract
/// medication information from handwritten or printed prescriptions
class AIPrescriptionScannerService {
  // Common medication database for validation and confidence boosting
  static const List<String> _knownMedications = [
    // Pain relievers
    'acetaminophen',
    'paracetamol', // British/International name for acetaminophen
    'ibuprofen',
    'aspirin',
    'naproxen',
    'diclofenac',
    'celecoxib',
    'tramadol',
    'morphine',
    'oxycodone',
    'hydrocodone',
    'codeine',
    'fentanyl',
    // Antibiotics
    'amoxicillin',
    'azithromycin',
    'ciprofloxacin',
    'doxycycline',
    'cephalexin',
    'metronidazole',
    'clarithromycin',
    'levofloxacin',
    'clindamycin',
    'penicillin',
    'ampicillin',
    'erythromycin',
    'tetracycline',
    'vancomycin',
    'gentamicin',
    // Cardiovascular
    'amlodipine',
    'lisinopril',
    'atenolol',
    'metoprolol',
    'losartan',
    'valsartan',
    'carvedilol',
    'enalapril',
    'ramipril',
    'bisoprolol',
    'warfarin',
    'clopidogrel',
    'atorvastatin',
    'simvastatin',
    'rosuvastatin',
    'pravastatin',
    'digoxin',
    'furosemide',
    'spironolactone',
    'hydrochlorothiazide',
    // Diabetes
    'metformin',
    'glipizide',
    'glyburide',
    'insulin',
    'sitagliptin',
    'empagliflozin',
    'liraglutide',
    'canagliflozin',
    'pioglitazone',
    // Respiratory
    'albuterol',
    'salbutamol',
    'montelukast',
    'fluticasone',
    'budesonide',
    'ipratropium',
    'tiotropium',
    'prednisone',
    'prednisolone',
    // GI medications
    'omeprazole',
    'pantoprazole',
    'esomeprazole',
    'ranitidine',
    'famotidine',
    'ondansetron',
    'metoclopramide',
    'loperamide',
    'lactulose',
    'bisacodyl',
    // Mental health
    'sertraline',
    'fluoxetine',
    'escitalopram',
    'citalopram',
    'paroxetine',
    'venlafaxine',
    'duloxetine',
    'mirtazapine',
    'bupropion',
    'trazodone',
    'alprazolam',
    'lorazepam',
    'diazepam',
    'clonazepam',
    'zolpidem',
    'quetiapine',
    'risperidone',
    'olanzapine',
    'aripiprazole',
    // Thyroid
    'levothyroxine',
    'liothyronine',
    'methimazole',
    'propylthiouracil',
    // Other common
    'gabapentin',
    'pregabalin',
    'cyclobenzaprine',
    'baclofen',
    'tamsulosin',
    'finasteride',
    'sildenafil',
    'tadalafil',
    'hydroxyzine',
    'diphenhydramine',
    'cetirizine',
    'loratadine',
    'fexofenadine',
    'vitamin d',
    'calcium',
    'vitamin b12',
    'folic acid',
    'iron',
  ];

  // Medical terminology context keywords
  static const List<String> _medicalContextKeywords = [
    'rx',
    'prescription',
    'medication',
    'drug',
    'medicine',
    'take',
    'administer',
    'sig',
    'dispense',
    'patient',
    'doctor',
    'physician',
    'pharmacy',
    'dosage',
    'dose',
    'mg',
    'mcg',
    'tablet',
    'capsule',
    'ml',
  ];

  /// Scan and extract medication information from an image
  Future<Map<String, dynamic>> scanPrescription(File imageFile) async {
    try {
      print('\n🔍 STARTING PRESCRIPTION SCAN');
      print('📁 Image file: ${imageFile.path}');
      final fileSize = await imageFile.length();
      print('📏 File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');

      // Step 1: Preprocess image for better handwriting recognition
      print('\n🎨 PREPROCESSING IMAGE...');
      final preprocessedFile = await _preprocessImage(imageFile);
      print('✅ Image preprocessed successfully');

      // Step 2: Initialize text recognizer
      final textRecognizer = TextRecognizer();

      // Step 3: Try multiple OCR attempts with different approaches
      RecognizedText? recognizedText;

      // Attempt 1: Original image
      print('\n📸 OCR ATTEMPT 1: Original image');
      recognizedText = await textRecognizer.processImage(
        InputImage.fromFile(imageFile),
      );
      print(
        '   Result: ${recognizedText.text.length} characters, ${recognizedText.blocks.length} blocks',
      );

      // Attempt 2: Preprocessed image (if first attempt failed)
      if (recognizedText.text.isEmpty && preprocessedFile != null) {
        print('\n📸 OCR ATTEMPT 2: Enhanced image (contrast/brightness)');
        recognizedText = await textRecognizer.processImage(
          InputImage.fromFile(preprocessedFile),
        );
        print(
          '   Result: ${recognizedText.text.length} characters, ${recognizedText.blocks.length} blocks',
        );
      }

      // Debug: Print raw OCR results
      print('\n=== AI PRESCRIPTION SCANNER (HANDWRITING MODE) ===');
      print('Raw text length: ${recognizedText.text.length} characters');
      print('Text blocks: ${recognizedText.blocks.length}');

      if (recognizedText.blocks.isNotEmpty) {
        print('\n📝 DETECTED TEXT BLOCKS:');
        for (int i = 0; i < recognizedText.blocks.length && i < 10; i++) {
          final block = recognizedText.blocks[i];
          print('   Block ${i + 1}: "${block.text}"');
        }
      }

      // Check if we have any text
      if (recognizedText.text.isEmpty) {
        print('\n❌ NO TEXT DETECTED - Possible issues:');
        print('   • Handwriting too light or unclear');
        print('   • Poor lighting conditions');
        print('   • Text too small or blurry');
        print('   • Camera not focused properly');
        textRecognizer.close();
        if (preprocessedFile != null && await preprocessedFile.exists()) {
          await preprocessedFile.delete();
        }
        return {
          'medicationName': '',
          'dosage': '',
          'repeatInterval': 'Daily',
          'numberOfIntakes': '',
          'times': <String>[],
          'confidence': 0.0,
          'error':
              '❌ No text detected. Please ensure:\n• Good lighting\n• Clear, dark handwriting\n• Camera focused properly',
        };
      }

      // Close the recognizer
      textRecognizer.close();

      // Clean up preprocessed file
      if (preprocessedFile != null && await preprocessedFile.exists()) {
        await preprocessedFile.delete();
      }

      // Step 4: Analyze the recognized text with AI-powered parsing
      final extractedData = _intelligentParse(recognizedText);

      return extractedData;
    } catch (e, stackTrace) {
      print('❌ ERROR in AI prescription scanning: $e');
      print('Stack trace: $stackTrace');
      return {..._getEmptyResult(), 'error': '❌ Scanner error: $e'};
    }
  }

  /// Preprocess image to enhance handwriting visibility
  /// Applies contrast, brightness, and sharpening for better OCR
  Future<File?> _preprocessImage(File imageFile) async {
    try {
      // Read the image
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) {
        print('⚠️ Failed to decode image');
        return null;
      }

      print('   Original: ${image.width}x${image.height}');

      // Step 1: Convert to grayscale for better text recognition
      image = img.grayscale(image);
      print('   ✓ Converted to grayscale');

      // Step 2: CURSIVE ENHANCEMENT - Apply binary thresholding
      // This separates connected letters by making text pure black/white
      image = _applyBinaryThreshold(image, threshold: 128);
      print('   ✓ Binary threshold applied (cursive separation)');

      // Step 3: Increase contrast (makes dark text darker, light background lighter)
      image = img.adjustColor(image, contrast: 2.0);
      print('   ✓ Contrast enhanced (+100% for cursive)');

      // Step 4: Increase brightness slightly
      image = img.adjustColor(image, brightness: 1.3);
      print('   ✓ Brightness adjusted (+30% for cursive)');

      // Step 5: Apply sharpening to make cursive strokes clearer
      image = img.adjustColor(
        image,
        saturation: 0,
      ); // Remove any color artifacts
      image = _sharpenImage(image); // Extra sharpening for cursive
      print('   ✓ Sharpened (enhanced for cursive)');

      // Step 6: Optional - increase size for small text
      if (image.width < 1200) {
        final scale = 1200 / image.width;
        image = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.cubic,
        );
        print('   ✓ Upscaled to ${image.width}x${image.height}');
      }

      // Save preprocessed image
      final preprocessedPath =
          '${imageFile.parent.path}${Platform.pathSeparator}preprocessed_${imageFile.uri.pathSegments.last}';
      final preprocessedFile = File(preprocessedPath);
      await preprocessedFile.writeAsBytes(img.encodeJpg(image, quality: 95));

      print('   ✓ Saved preprocessed image: ${preprocessedFile.path}');
      return preprocessedFile;
    } catch (e) {
      print('⚠️ Image preprocessing failed: $e');
      return null;
    }
  }

  /// AI-powered intelligent parsing of prescription text
  Map<String, dynamic> _intelligentParse(RecognizedText recognizedText) {
    // Analyze text blocks with spatial awareness
    final textBlocks = recognizedText.blocks;

    // Build context from all text
    String fullText = recognizedText.text;

    // Normalize common handwriting OCR errors BEFORE processing
    fullText = _normalizeHandwritingErrors(fullText);

    final lowerText = fullText.toLowerCase();

    print('=== AI Prescription Scanner (Handwriting Mode) ===');
    print('Raw text length: ${fullText.length} characters');
    print('Text blocks: ${textBlocks.length}');

    // Check if this looks like a prescription (has medical context)
    final hasMedicalContext = _hasMedicalContext(lowerText);
    print('Has medical context: $hasMedicalContext');

    // Extract components using AI algorithms
    final medicationName = _extractMedicationNameAI(textBlocks, lowerText);
    final dosage = _extractDosageAI(textBlocks, lowerText, medicationName);
    final frequency = _extractFrequencyAI(textBlocks, lowerText);
    final duration = _extractDurationAI(textBlocks, lowerText);
    final times = _inferTimesFromFrequency(frequency);

    print('✅ CORRECTED MEDICATION: $medicationName');
    print('   Dosage: $dosage');
    print('   Frequency: $frequency');
    print('   Duration: $duration');
    print('================================');

    return {
      'medicationName': medicationName,
      'dosage': dosage,
      'repeatInterval': frequency,
      'numberOfIntakes': duration,
      'times': times,
      'confidence': _calculateOverallConfidence(
        medicationName,
        dosage,
        frequency,
        hasMedicalContext,
      ),
    };
  }

  /// Check if text contains medical/prescription context
  bool _hasMedicalContext(String lowerText) {
    int contextScore = 0;
    for (final keyword in _medicalContextKeywords) {
      if (lowerText.contains(keyword)) {
        contextScore++;
      }
    }
    return contextScore >= 2; // At least 2 medical keywords
  }

  /// Normalize common handwriting OCR errors
  String _normalizeHandwritingErrors(String text) {
    // Common OCR mistakes with handwritten text
    String normalized = text;

    // Number confusions
    normalized = normalized
        .replaceAll(RegExp(r'\b0(?=\d)'), 'O') // 0 misread as O at word start
        .replaceAll(RegExp(r'(?<=\d)O\b'), '0') // O misread as 0 at word end
        .replaceAll(RegExp(r'\bl(?=\d)'), '1') // lowercase L as 1
        .replaceAll(RegExp(r'\bI(?=\d)'), '1') // capital I as 1
        .replaceAll(RegExp(r'(?<=\d)l\b'), '1') // l at end of number
        .replaceAll(RegExp(r'S(?=\d)'), '5') // S misread as 5
        .replaceAll(RegExp(r'Z(?=\d)'), '2'); // Z misread as 2

    // Letter confusions common in prescriptions
    normalized = normalized
        .replaceAll(RegExp(r'\brn\b', caseSensitive: false), 'm') // rn → m
        .replaceAll(RegExp(r'\bvv\b', caseSensitive: false), 'w') // vv → w
        .replaceAll(RegExp(r'\bcl\b', caseSensitive: false), 'd') // cl → d
        .replaceAll(RegExp(r'ii', caseSensitive: false), 'u'); // ii → u

    // Cursive-specific error patterns (aggressive matching for bad OCR)
    normalized = normalized
        .replaceAll(
          RegExp('arae', caseSensitive: false),
          'para',
        ) // "arae" → "para" (paracetamol)
        .replaceAll(
          RegExp('tamno', caseSensitive: false),
          'tamol',
        ) // "tamno" → "tamol"
        .replaceAll(
          RegExp('tarnno', caseSensitive: false),
          'tamol',
        ) // "tarnno" → "tamol"
        .replaceAll(
          RegExp('tarnol', caseSensitive: false),
          'tamol',
        ) // "tarnol" → "tamol"
        .replaceAll(
          RegExp('acet', caseSensitive: false),
          'acet',
        ) // preserve "acet"
        .replaceAll(
          RegExp('ibupr', caseSensitive: false),
          'ibupro',
        ) // "ibupr" → "ibupro"
        .replaceAll(
          RegExp('aspir', caseSensitive: false),
          'aspir',
        ); // preserve "aspir"

    // Normalize spacing around units (common in handwriting)
    normalized = normalized
        .replaceAll(RegExp(r'(\d)\s*m\s*g'), r'\$1mg')
        .replaceAll(RegExp(r'(\d)\s*m\s*l'), r'\$1ml')
        .replaceAll(RegExp(r'(\d)\s*m\s*c\s*g'), r'\$1mcg')
        .replaceAll(RegExp(r'(\d)\s*g\s*(?=\s|$)'), r'\$1g'); // Fix "50 g"

    return normalized;
  }

  /// AI-powered medication name extraction using spatial and contextual analysis
  String _extractMedicationNameAI(
    List<TextBlock> textBlocks,
    String lowerText,
  ) {
    final candidates = <Map<String, dynamic>>[];

    // Strategy 1: Look for explicit labels (RX, Medication, Drug name, etc.)
    // More lenient for handwriting
    for (final block in textBlocks) {
      final blockText = block.text.toLowerCase();

      // Check if this block is a label (allow more variations)
      if (RegExp(
        r'\b(rx|r\.?x\.?|medication|med|drug|medicine|name)\b',
      ).hasMatch(blockText)) {
        // Look for the next block (likely the medication name)
        final blockIndex = textBlocks.indexOf(block);
        if (blockIndex < textBlocks.length - 1) {
          final nextBlock = textBlocks[blockIndex + 1];
          final candidateName = nextBlock.text.trim();

          if (_isValidMedicationName(candidateName)) {
            // Try fuzzy matching
            final fuzzyMatched = _fuzzyMatchMedication(candidateName);
            final finalName = fuzzyMatched != candidateName
                ? fuzzyMatched
                : candidateName;

            candidates.add({
              'name': finalName,
              'confidence': 0.95,
              'method': 'label_based',
            });
          }
        }

        // Also check same line after the label
        final parts = block.text.split(RegExp(r'[:.\s]+'));
        if (parts.length >= 2) {
          final candidateFromSameLine = parts.sublist(1).join(' ').trim();
          if (_isValidMedicationName(candidateFromSameLine)) {
            final fuzzyMatched = _fuzzyMatchMedication(candidateFromSameLine);
            final finalName = fuzzyMatched != candidateFromSameLine
                ? fuzzyMatched
                : candidateFromSameLine;

            candidates.add({
              'name': finalName,
              'confidence': 0.93,
              'method': 'label_based_sameline',
            });
          }
        }
      }
    }

    // Strategy 2: Check against known medication database (with fuzzy matching for handwriting)
    for (final block in textBlocks) {
      // Clean text - remove extra spaces and normalize
      final cleanedText = block.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final words = cleanedText.split(' ');

      // ENHANCEMENT: Try combining multiple words for misspelled medication names
      // Example: "ace tamimoplen" → "acetamimoplen" → "acetaminophen"
      for (var i = 0; i < words.length; i++) {
        // Try 1-word, 2-word, and 3-word combinations
        for (
          var wordCount = 1;
          wordCount <= 3 && i + wordCount <= words.length;
          wordCount++
        ) {
          final combinedWords = words.sublist(i, i + wordCount).join('');
          final word = combinedWords.toLowerCase().trim();

          // Skip very short or completely non-alphabetic
          if (word.length < 3) continue;

          // Exact single word match
          if (_knownMedications.contains(word)) {
            candidates.add({
              'name': _properCase(word),
              'confidence': 0.95,
              'method': 'exact_database_match',
            });
          } else {
            // Fuzzy match for handwriting errors (handles spaces + misspelling)
            final fuzzyMatched = _fuzzyMatchMedication(combinedWords);
            if (fuzzyMatched != combinedWords &&
                _knownMedications.contains(fuzzyMatched.toLowerCase())) {
              // Found a close match - this handles "ace tamimoplen" → "Acetaminophen"
              candidates.add({
                'name': fuzzyMatched,
                'confidence': 0.90,
                'method': 'fuzzy_database_match',
              });
            }
          }
        }
      }
    }

    // Strategy 3: Pattern-based extraction (more lenient for handwriting)
    for (final block in textBlocks) {
      final lines = block.text.split('\n');

      for (final line in lines) {
        final trimmedLine = line.trim();

        // Skip if too short or contains non-medication indicators
        if (trimmedLine.length < 3) continue;
        if (_containsNonMedicationKeywords(trimmedLine.toLowerCase())) continue;

        // More lenient pattern for handwritten text (allows more variations)
        final medPattern = RegExp(
          r'^[A-Za-z][a-zA-Z]{2,}(?:[\s-][A-Za-z][a-zA-Z]{2,})*$',
        );

        if (medPattern.hasMatch(trimmedLine)) {
          final confidence = _calculateNameConfidence(
            trimmedLine.toLowerCase(),
          );

          if (confidence > 0.4) {
            // Lower threshold for handwriting
            // Try fuzzy matching first
            final fuzzyMatched = _fuzzyMatchMedication(trimmedLine);
            final finalName = fuzzyMatched != trimmedLine
                ? fuzzyMatched
                : trimmedLine;

            candidates.add({
              'name': finalName,
              'confidence':
                  confidence *
                  (fuzzyMatched != trimmedLine
                      ? 1.1
                      : 1.0), // Boost if fuzzy matched
              'method': fuzzyMatched != trimmedLine
                  ? 'pattern_with_fuzzy'
                  : 'pattern_based',
            });
          }
        }
      }
    }

    // Strategy 4: Look at the top portion of the prescription (typically has drug name)
    if (textBlocks.isNotEmpty) {
      final topBlocks = textBlocks.take(3).toList();

      for (final block in topBlocks) {
        final words = block.text.split(RegExp(r'\s+'));

        for (final word in words) {
          if (word.length >= 4 &&
              word[0] == word[0].toUpperCase() &&
              !_containsNonMedicationKeywords(word.toLowerCase())) {
            final confidence = _calculateNameConfidence(word.toLowerCase());

            if (confidence > 0.4) {
              candidates.add({
                'name': word,
                'confidence':
                    confidence * 0.85, // Slight penalty for position-only
                'method': 'top_position',
              });
            }
          }
        }
      }
    }

    // Sort candidates by confidence
    candidates.sort(
      (a, b) =>
          (b['confidence'] as double).compareTo(a['confidence'] as double),
    );

    // Debug output
    if (candidates.isNotEmpty) {
      print('Top medication candidates:');
      for (var i = 0; i < candidates.length && i < 5; i++) {
        print(
          '  ${candidates[i]['name']} - ${candidates[i]['confidence'].toStringAsFixed(2)} (${candidates[i]['method']})',
        );
      }
    }

    return candidates.isNotEmpty ? candidates.first['name'] as String : '';
  }

  /// Convert medication name to proper case (first letter uppercase)
  String _properCase(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  /// Calculate phonetic similarity for cursive OCR errors
  /// "arae tamno" vs "paracetamol" → checks if sounds similar
  double _calculatePhoneticSimilarity(String s1, String s2) {
    // Simplify to phonetic codes (remove silent letters, similar sounds)
    String phonetic1 = _toPhonetic(s1);
    String phonetic2 = _toPhonetic(s2);

    if (phonetic1.isEmpty || phonetic2.isEmpty) return 0.0;

    // Calculate similarity of phonetic codes
    final distance = _levenshteinDistance(phonetic1, phonetic2);
    final maxLen = phonetic1.length > phonetic2.length
        ? phonetic1.length
        : phonetic2.length;
    return 1.0 - (distance / maxLen);
  }

  /// Convert text to phonetic representation
  String _toPhonetic(String text) {
    String phonetic = text.toLowerCase();

    // Remove silent/confusing letters common in cursive OCR errors
    phonetic = phonetic.replaceAll(
      RegExp(r'[aeiou]'),
      '',
    ); // Remove vowels (cursive often misreads)
    phonetic = phonetic.replaceAll(
      RegExp(r'[^a-z]'),
      '',
    ); // Keep only consonants

    // Combine similar sounds
    phonetic = phonetic.replaceAll('ph', 'f');
    phonetic = phonetic.replaceAll('c', 'k');
    phonetic = phonetic.replaceAll('x', 'ks');
    phonetic = phonetic.replaceAll('z', 's');

    return phonetic;
  }

  /// Apply binary thresholding to separate cursive letters
  /// Converts grayscale to pure black/white for better OCR
  img.Image _applyBinaryThreshold(img.Image image, {int threshold = 128}) {
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel);

        // Convert to pure black or white based on threshold
        final newPixel = luminance < threshold
            ? img.ColorInt8.rgb(0, 0, 0) // Black (text)
            : img.ColorInt8.rgb(255, 255, 255); // White (background)

        image.setPixel(x, y, newPixel);
      }
    }
    return image;
  }

  /// Sharpen image to enhance cursive stroke clarity
  img.Image _sharpenImage(img.Image image) {
    // Apply unsharp mask for edge enhancement
    final kernel = [0, -1, 0, -1, 5, -1, 0, -1, 0];

    final sharpened = img.Image(width: image.width, height: image.height);

    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        int sum = 0;
        int index = 0;

        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixel = image.getPixel(x + kx, y + ky);
            final luminance = img.getLuminance(pixel);
            sum += (luminance * kernel[index]).toInt();
            index++;
          }
        }

        // Clamp to 0-255 range
        final value = sum.clamp(0, 255);
        final newPixel = img.ColorInt8.rgb(value, value, value);
        sharpened.setPixel(x, y, newPixel);
      }
    }

    return sharpened;
  }

  /// Calculate Levenshtein distance for fuzzy matching (handles OCR errors)
  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final len1 = s1.length;
    final len2 = s2.length;
    List<List<int>> matrix = List.generate(
      len1 + 1,
      (i) => List.filled(len2 + 1, 0),
    );

    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        int cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[len1][len2];
  }

  /// Fuzzy match medication names (handles handwriting OCR errors)
  /// SMART CORRECTION: "ace tamimoplen" → "acetaminophen"
  String _fuzzyMatchMedication(String candidate) {
    final originalCandidate = candidate;

    // Step 1: Remove ALL spaces (handwriting often has spaces in wrong places)
    // "ace tamimoplen" → "acetamimoplen"
    String lowerCandidate = candidate.toLowerCase().trim().replaceAll(
      RegExp(r'\s+'),
      '',
    );

    print(
      '🔍 Fuzzy matching: "$originalCandidate" → cleaned: "$lowerCandidate"',
    );

    // Step 2: Exact match first
    if (_knownMedications.contains(lowerCandidate)) {
      final corrected = _properCase(lowerCandidate);
      print('   ✅ Exact match found: $corrected');
      return corrected;
    }

    // Step 3: Find closest match using Levenshtein distance
    String? bestMatch;
    int bestDistance = 999999;
    double bestSimilarity = 0.0;

    for (final knownMed in _knownMedications) {
      final distance = _levenshteinDistance(lowerCandidate, knownMed);

      // Calculate similarity percentage
      final maxLen = lowerCandidate.length > knownMed.length
          ? lowerCandidate.length
          : knownMed.length;
      final similarity = 1.0 - (distance / maxLen);

      // AGGRESSIVE THRESHOLD for cursive handwriting
      // Cursive OCR can be VERY bad: "paracetamol" → "arae tamno" (8 chars diff!)
      int threshold;
      if (knownMed.length > 10) {
        threshold = 6; // Allow 6 character differences for long words (cursive)
      } else if (knownMed.length > 8) {
        threshold = 5; // Allow 5 for medium-long words
      } else if (knownMed.length > 5) {
        threshold = 3; // Allow 3 for short words
      } else {
        threshold = 2; // Allow 2 for very short words
      }

      // BONUS: Check phonetic similarity for cursive
      // "arae" sounds like "para", "tamno" sounds like "tamol"
      final phoneticSimilarity = _calculatePhoneticSimilarity(
        lowerCandidate,
        knownMed,
      );
      if (phoneticSimilarity > 0.6) {
        threshold += 2; // Allow 2 more errors if phonetically similar
      }

      // Keep track of best match
      if (distance < bestDistance && distance <= threshold) {
        bestDistance = distance;
        bestMatch = knownMed;
        bestSimilarity = similarity;
      }
    }

    if (bestMatch != null) {
      final corrected = _properCase(bestMatch);
      print(
        '   ✅ Fuzzy match: "$originalCandidate" → "$corrected" (distance: $bestDistance, similarity: ${(bestSimilarity * 100).toStringAsFixed(0)}%)',
      );
      // Return corrected medication name with proper capitalization
      return corrected;
    }

    print('   ❌ No match found for "$originalCandidate"');
    return candidate;
  }

  /// Validate if a string looks like a medication name
  bool _isValidMedicationName(String name) {
    if (name.length < 3) return false;
    if (RegExp(r'\d').hasMatch(name)) return false; // No numbers in name
    if (_containsNonMedicationKeywords(name.toLowerCase())) return false;
    return true;
  }

  /// Check if text contains keywords that indicate it's NOT a medication name
  bool _containsNonMedicationKeywords(String lowerText) {
    const nonMedKeywords = [
      'take',
      'with',
      'food',
      'water',
      'daily',
      'times',
      'day',
      'week',
      'month',
      'morning',
      'evening',
      'night',
      'before',
      'after',
      'meal',
      'doctor',
      'patient',
      'pharmacy',
      'refill',
      'date',
      'signature',
      'quantity',
      'dispense',
      'directions',
      'tablet',
      'capsule',
      'pill',
      'dose',
      'amount',
    ];

    return nonMedKeywords.any((keyword) => lowerText.contains(keyword));
  }

  /// Calculate confidence score for a medication name candidate
  double _calculateNameConfidence(String lowerName) {
    double confidence = 0.5; // Base confidence

    // Boost: Known medication match
    if (_knownMedications.contains(lowerName)) {
      confidence += 0.4;
    }

    // Boost: Partial match with known medications
    for (final knownMed in _knownMedications) {
      if (knownMed.contains(lowerName) || lowerName.contains(knownMed)) {
        confidence += 0.3;
        break;
      }
    }

    // Boost: Common medication suffixes
    const medSuffixes = [
      'cillin',
      'mycin',
      'oxin',
      'azole',
      'pril',
      'olol',
      'statin',
      'dipine',
      'sartan',
      'tidine',
      'prazole',
      'fen',
      'done',
      'ine',
      'zole',
      'mab',
      'vir',
    ];

    for (final suffix in medSuffixes) {
      if (lowerName.endsWith(suffix)) {
        confidence += 0.25;
        break;
      }
    }

    // Boost: Length (longer names are often medications)
    if (lowerName.length > 8) confidence += 0.1;
    if (lowerName.length > 12) confidence += 0.1;

    // Penalty: Very short names
    if (lowerName.length < 5) confidence -= 0.2;

    return confidence.clamp(0.0, 1.0);
  }

  /// AI-powered dosage extraction with context awareness
  String _extractDosageAI(
    List<TextBlock> textBlocks,
    String lowerText,
    String medicationName,
  ) {
    print('\n🔍 DOSAGE EXTRACTION STARTED');
    print('Full text to scan: "$lowerText"');
    print('Text blocks count: ${textBlocks.length}');

    final candidates = <Map<String, dynamic>>[];

    // STRATEGY 0: EMERGENCY SCAN - Find ANY number and ANY unit-like text nearby
    print('  Strategy 0 (EMERGENCY): Finding ANY numbers and units');
    final allNumbers = <String>[];
    final allUnits = <String>[];

    for (var block in textBlocks) {
      final text = block.text.trim();
      // Find numbers
      if (RegExp(r'^\d+$').hasMatch(text)) {
        allNumbers.add(text);
        print('    Found number: "$text"');
      }
      // Find unit-like words (mg, dmg, rng, ml, etc.)
      if (RegExp(r'^[drmn]?[mg]l?g?$', caseSensitive: false).hasMatch(text)) {
        allUnits.add(text);
        print('    Found unit-like: "$text"');
      }
    }

    // Combine all numbers with all units
    if (allNumbers.isNotEmpty && allUnits.isNotEmpty) {
      for (var number in allNumbers) {
        for (var unit in allUnits) {
          final combined = '$number$unit';
          print('    Emergency combination: "$number" + "$unit" = "$combined"');
          final extracted = _extractDosageFromText(combined);
          if (extracted.isNotEmpty) {
            print('    ✅✅✅ EMERGENCY EXTRACTION SUCCESS: $extracted');
            candidates.add({
              'dosage': extracted,
              'confidence': 0.99, // HIGHEST PRIORITY
              'method': 'emergency_number_unit_match',
            });
          }
        }
      }
    }

    // Strategy 1: Look for explicit dosage labels
    final dosageLabelPattern = RegExp(
      r'(?:dosage|dose|strength|amount)[:.\s]*([^\n]{1,30})',
      caseSensitive: false,
    );

    final labelMatch = dosageLabelPattern.firstMatch(lowerText);
    if (labelMatch != null) {
      print('  Strategy 1: Found dosage label');
      final dosageText = labelMatch.group(1)!.trim();
      print('    Label text: "$dosageText"');
      final extracted = _extractDosageFromText(dosageText);
      if (extracted.isNotEmpty) {
        print('    ✅ Extracted: $extracted');
        candidates.add({
          'dosage': extracted,
          'confidence': 0.95,
          'method': 'label_based',
        });
      }
    }

    // Strategy 2: Look near medication name (spatial analysis)
    if (medicationName.isNotEmpty) {
      for (final block in textBlocks) {
        if (block.text.toLowerCase().contains(medicationName.toLowerCase())) {
          // Check this block and next blocks
          final blockIndex = textBlocks.indexOf(block);

          for (
            var i = blockIndex;
            i < blockIndex + 3 && i < textBlocks.length;
            i++
          ) {
            final searchText = textBlocks[i].text.toLowerCase();
            final extracted = _extractDosageFromText(searchText);

            if (extracted.isNotEmpty) {
              candidates.add({
                'dosage': extracted,
                'confidence': 0.85 - (0.05 * (i - blockIndex)),
                'method': 'spatial_proximity',
              });
            }
          }
        }
      }
    }

    // Strategy 3: General dosage pattern matching on full text
    print('  Strategy 3: Scanning full text for dosage patterns');
    final dosagePattern = RegExp(
      r'(\d+(?:\.\d+)?\s*(?:mg|g|ml|mcg|µg|microgram|milligram|gram|milliliter|unit|iu|tablet|cap|capsule))',
      caseSensitive: false,
    );

    final matches = dosagePattern.allMatches(lowerText);
    for (final match in matches) {
      final dosage = match.group(1)!.trim();
      print('    Found pattern: "$dosage"');
      candidates.add({
        'dosage': dosage,
        'confidence': 0.7,
        'method': 'pattern_match',
      });
    }

    // Strategy 4: Scan EACH text block individually (most aggressive)
    print('  Strategy 4: Scanning each text block individually');
    for (var i = 0; i < textBlocks.length; i++) {
      final blockText = textBlocks[i].text;
      print('    Block $i text: "$blockText"');
      final extracted = _extractDosageFromText(blockText);
      if (extracted.isNotEmpty) {
        print('    ✅ Block $i extracted: $extracted');
        candidates.add({
          'dosage': extracted,
          'confidence': 0.8,
          'method': 'individual_block_scan',
        });
      }
    }

    // Strategy 5: SMART COMBINATION - Combine adjacent blocks (handles split dosages)
    // Example: Block "50" + Block "Dmg" → "50mg"
    print('  Strategy 5: Combining adjacent blocks for split dosages');
    for (var i = 0; i < textBlocks.length - 1; i++) {
      final currentBlock = textBlocks[i].text.trim();
      final nextBlock = textBlocks[i + 1].text.trim();

      // Check if current block is a number and next block looks like a unit
      if (RegExp(r'^\d+$').hasMatch(currentBlock)) {
        final combined = '$currentBlock$nextBlock';
        print(
          '    Trying combination: "$currentBlock" + "$nextBlock" = "$combined"',
        );
        final extracted = _extractDosageFromText(combined);
        if (extracted.isNotEmpty) {
          print('    ✅ Combined blocks $i+${i + 1} extracted: $extracted');
          candidates.add({
            'dosage': extracted,
            'confidence': 0.9, // High confidence for smart combination
            'method': 'smart_block_combination',
          });
        }
      }

      // Also try with space between
      final combinedWithSpace = '$currentBlock $nextBlock';
      final extractedWithSpace = _extractDosageFromText(combinedWithSpace);
      if (extractedWithSpace.isNotEmpty &&
          !candidates.any((c) => c['dosage'] == extractedWithSpace)) {
        print(
          '    ✅ Combined with space blocks $i+${i + 1} extracted: $extractedWithSpace',
        );
        candidates.add({
          'dosage': extractedWithSpace,
          'confidence': 0.85,
          'method': 'smart_block_combination_spaced',
        });
      }
    }

    // Sort by confidence
    candidates.sort(
      (a, b) =>
          (b['confidence'] as double).compareTo(a['confidence'] as double),
    );

    if (candidates.isNotEmpty) {
      print('Top dosage candidates:');
      for (var i = 0; i < candidates.length && i < 3; i++) {
        print(
          '  ${candidates[i]['dosage']} - ${candidates[i]['confidence'].toStringAsFixed(2)} (${candidates[i]['method']})',
        );
      }
    }

    return candidates.isNotEmpty ? candidates.first['dosage'] as String : '';
  }

  /// Extract dosage information from a text string (handles OCR errors)
  String _extractDosageFromText(String text) {
    print('      _extractDosageFromText input: "$text"');
    // Normalize OCR errors BEFORE pattern matching (cursive-friendly)
    String normalized = text.toLowerCase();

    // AGGRESSIVE cursive letter-to-number corrections (e.g., "SDMG" → "50MG")
    // Must run FIRST before other replacements
    normalized = normalized
        .replaceAll(
          RegExp(r'\bsd(?=mg|ml|g\b)', caseSensitive: false),
          '50',
        ) // SD → 50
        .replaceAll(
          RegExp(r'\bs0(?=mg|ml|g\b)', caseSensitive: false),
          '50',
        ) // S0 → 50
        .replaceAll(
          RegExp(r'\bso(?=mg|ml|g\b)', caseSensitive: false),
          '50',
        ) // SO → 50
        .replaceAll(
          RegExp(r'\bid(?=mg|ml|g\b)', caseSensitive: false),
          '10',
        ) // ID → 10
        .replaceAll(
          RegExp(r'\bio(?=mg|ml|g\b)', caseSensitive: false),
          '10',
        ) // IO → 10
        .replaceAll(
          RegExp(r'\bil(?=mg|ml|g\b)', caseSensitive: false),
          '11',
        ) // IL → 11
        .replaceAll(
          RegExp(r'\bzd(?=mg|ml|g\b)', caseSensitive: false),
          '20',
        ) // ZD → 20
        .replaceAll(
          RegExp(r'\bzo(?=mg|ml|g\b)', caseSensitive: false),
          '20',
        ) // ZO → 20
        .replaceAll(
          RegExp(r'\bz0(?=mg|ml|g\b)', caseSensitive: false),
          '20',
        ) // Z0 → 20
        .replaceAll(
          RegExp(r'\bss(?=mg|ml|g\b)', caseSensitive: false),
          '55',
        ) // SS → 55
        .replaceAll(
          RegExp(r'\bdd(?=mg|ml|g\b)', caseSensitive: false),
          '00',
        ) // DD → 00
        .replaceAll(
          RegExp(r'\bloo(?=mg|ml|g\b)', caseSensitive: false),
          '100',
        ) // LOO → 100
        .replaceAll(
          RegExp(r'\bioo(?=mg|ml|g\b)', caseSensitive: false),
          '100',
        ); // IOO → 100

    // Standard cursive number OCR errors (individual characters)
    normalized = normalized
        .replaceAll(RegExp(r'\bO(?=\d)'), '0') // O → 0 before digits
        .replaceAll(RegExp(r'(?<=\d)O\b'), '0') // O → 0 after digits
        .replaceAll(RegExp(r'\bl(?=\d)'), '1') // l → 1
        .replaceAll(RegExp(r'\bI(?=\d)'), '1') // I → 1
        .replaceAll(RegExp(r'\bS(?=\d)'), '5') // S → 5
        .replaceAll(RegExp(r'\bZ(?=\d)'), '2') // Z → 2
        .replaceAll(RegExp(r'(?<=\d)D\b'), '0') // D → 0 at end (5D → 50)
        .replaceAll(RegExp(r'(?<=\d)d\b'), '0'); // d → 0 at end (5d → 50)

    // Fix common cursive unit OCR errors (MUST COME BEFORE OTHER REPLACEMENTS)
    normalized = normalized
        .replaceAll(RegExp(r'\bdmg\b', caseSensitive: false), 'mg') // Dmg → mg
        .replaceAll(RegExp(r'\bdml\b', caseSensitive: false), 'ml') // Dml → ml
        .replaceAll(RegExp(r'\brng\b', caseSensitive: false), 'mg') // rng → mg
        .replaceAll(RegExp(r'\brnl\b', caseSensitive: false), 'ml') // rnl → ml
        .replaceAll(RegExp(r'm\s*g'), 'mg') // Fix spacing in "m g"
        .replaceAll(RegExp(r'm\s*l'), 'ml') // Fix spacing in "m l"
        .replaceAll(RegExp(r'm\s*c\s*g'), 'mcg') // Fix "m c g"
        .replaceAll('ug', 'mcg')
        .replaceAll('µg', 'mcg')
        .replaceAll(RegExp(r'rn(?=\d)'), 'm'); // rn → m before digits

    print('      After normalization: "$normalized"');

    // ULTRA SIMPLE: Just find ANY number + mg/ml/g (MOST AGGRESSIVE)
    final superSimplePattern = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:mg|ml|mcg|g)\b',
      caseSensitive: false,
    );

    final simpleMatch = superSimplePattern.firstMatch(normalized);
    if (simpleMatch != null) {
      final fullMatch = simpleMatch.group(0)!.replaceAll(RegExp(r'\s+'), '');
      print('      ✅ SUPER SIMPLE match found: "$fullMatch"');
      return fullMatch;
    }

    // PRIMARY: Standard dosage pattern (most common)
    final dosagePattern = RegExp(
      r'(\d+(?:\.\d+)?\s*(?:mg|g|ml|mcg|microgram|milligram|gram|milliliter|unit|iu|units?|tablet|cap|capsule|tabs?|caps?))',
      caseSensitive: false,
    );

    final match = dosagePattern.firstMatch(normalized);
    if (match != null) {
      final dosage = match.group(1)!.trim();
      // Clean up spacing
      final cleaned = dosage.replaceAll(RegExp(r'\s+'), '');
      print('      ✅ Standard dosage match: "$cleaned"');
      return cleaned;
    }

    // FALLBACK: Very loose pattern for badly written cursive (e.g., "50mg")
    // Matches: digits + optional space/dot + 1-4 letter unit
    final loosePattern = RegExp(
      r'(\d+)[\s.\-]?([a-z]{1,4})',
      caseSensitive: false,
    );
    final looseMatches = loosePattern.allMatches(normalized);

    for (final looseMatch in looseMatches) {
      final number = looseMatch.group(1)!;
      final unit = looseMatch.group(2)!.toLowerCase();

      // Validate it's a real dosage unit (not random letters)
      if (RegExp(r'^(mg|ml|mcg|tab|cap|iu|g)$').hasMatch(unit)) {
        final result = '$number$unit';
        print('      ✅ Loose dosage match: "$result"');
        return result;
      }
    }

    print('      ❌ NO DOSAGE FOUND in text: "$normalized"');
    return '';
  }

  /// AI-powered frequency extraction
  String _extractFrequencyAI(List<TextBlock> textBlocks, String lowerText) {
    // Common frequency patterns with confidence scores
    final patterns = [
      {
        'pattern': r'once\s+(?:a\s+)?daily',
        'result': 'Daily',
        'confidence': 0.95,
      },
      {'pattern': r'qd|q\.d\.|od|o\.d\.', 'result': 'Daily', 'confidence': 0.9},
      {
        'pattern': r'twice\s+(?:a\s+)?daily|bid|b\.i\.d\.',
        'result': 'Twice daily',
        'confidence': 0.95,
      },
      {
        'pattern': r'three\s+times\s+(?:a\s+)?daily|tid|t\.i\.d\.',
        'result': 'Three times daily',
        'confidence': 0.95,
      },
      {
        'pattern': r'four\s+times\s+(?:a\s+)?daily|qid|q\.i\.d\.',
        'result': 'Four times daily',
        'confidence': 0.95,
      },
      {
        'pattern': r'every\s+(\d+)\s+hour',
        'result': 'Every {1} hours',
        'confidence': 0.9,
      },
      {
        'pattern': r'q\s*(\d+)\s*h',
        'result': 'Every {1} hours',
        'confidence': 0.85,
      },
      {
        'pattern': r'every\s+other\s+day',
        'result': 'Every other day',
        'confidence': 0.9,
      },
      {
        'pattern': r'weekly|once\s+(?:a\s+)?week',
        'result': 'Weekly',
        'confidence': 0.9,
      },
      {
        'pattern': r'monthly|once\s+(?:a\s+)?month',
        'result': 'Monthly',
        'confidence': 0.9,
      },
      {
        'pattern': r'as\s+needed|prn|p\.r\.n\.',
        'result': 'As needed',
        'confidence': 0.85,
      },
    ];

    for (final patternData in patterns) {
      final pattern = RegExp(
        patternData['pattern'] as String,
        caseSensitive: false,
      );

      final match = pattern.firstMatch(lowerText);
      if (match != null) {
        var result = patternData['result'] as String;

        // Replace placeholders with captured groups
        if (match.groupCount >= 1 && match.group(1) != null) {
          result = result.replaceAll('{1}', match.group(1)!);
        }

        print(
          'Frequency matched: $result (confidence: ${patternData['confidence']})',
        );
        return result;
      }
    }

    return 'Daily'; // Default
  }

  /// AI-powered duration extraction
  String _extractDurationAI(List<TextBlock> textBlocks, String lowerText) {
    final patterns = [
      RegExp(r'for\s+(\d+)\s+day', caseSensitive: false),
      RegExp(r'(\d+)\s+day\s+supply', caseSensitive: false),
      RegExp(r'for\s+(\d+)\s+week', caseSensitive: false),
      RegExp(r'(\d+)\s+week', caseSensitive: false),
      RegExp(r'for\s+(\d+)\s+month', caseSensitive: false),
      RegExp(r'(\d+)\s+month', caseSensitive: false),
      RegExp(r'quantity[:\s]+(\d+)', caseSensitive: false),
      RegExp(r'qty[:\s]+(\d+)', caseSensitive: false),
      RegExp(r'#(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(lowerText);
      if (match != null && match.groupCount >= 1) {
        final value = match.group(1)!;

        if (pattern.pattern.contains('day')) {
          return '$value days';
        } else if (pattern.pattern.contains('week')) {
          return '$value weeks';
        } else if (pattern.pattern.contains('month')) {
          return '$value months';
        } else {
          return '$value tablets';
        }
      }
    }

    return '';
  }

  /// Infer medication times from frequency
  List<TimeOfDay> _inferTimesFromFrequency(String frequency) {
    final lowerFreq = frequency.toLowerCase();

    if (lowerFreq.contains('twice') || lowerFreq.contains('bid')) {
      return [
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 21, minute: 0),
      ];
    } else if (lowerFreq.contains('three') || lowerFreq.contains('tid')) {
      return [
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 21, minute: 0),
      ];
    } else if (lowerFreq.contains('four') || lowerFreq.contains('qid')) {
      return [
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 12, minute: 0),
        const TimeOfDay(hour: 17, minute: 0),
        const TimeOfDay(hour: 21, minute: 0),
      ];
    } else {
      return [const TimeOfDay(hour: 9, minute: 0)];
    }
  }

  /// Calculate overall confidence score
  double _calculateOverallConfidence(
    String medicationName,
    String dosage,
    String frequency,
    bool hasMedicalContext,
  ) {
    double score = 0.0;

    if (medicationName.isNotEmpty) score += 0.4;
    if (dosage.isNotEmpty) score += 0.3;
    if (frequency.isNotEmpty) score += 0.2;
    if (hasMedicalContext) score += 0.1;

    return score;
  }

  /// Get empty result structure
  Map<String, dynamic> _getEmptyResult() {
    return {
      'medicationName': '',
      'dosage': '',
      'repeatInterval': 'Daily',
      'numberOfIntakes': '',
      'times': [const TimeOfDay(hour: 9, minute: 0)],
      'confidence': 0.0,
    };
  }
}
