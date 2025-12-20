import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/models/detection_record.dart';
import '../../core/services/detection_storage_service.dart';
import '../../core/services/fabric_classifier_service.dart';
import '../detection/detection_result_page.dart';

class CameraDetectionPage extends StatefulWidget {
  const CameraDetectionPage({
    super.key,
    this.selectedClassIndex,
    this.selectedClassName,
  });

  final int? selectedClassIndex;
  final String? selectedClassName;

  @override
  State<CameraDetectionPage> createState() => _CameraDetectionPageState();
}

class _CameraDetectionPageState extends State<CameraDetectionPage> {
  // Camera
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  String? _errorMessage;

  // Detection overlay state (shows last captured result)
  String _detectedClass = 'Ready to scan';
  double _confidence = 0;
  List<double> _scores = [];
  bool _isProcessingFrame = false;
  int _frameSkipCount = 0;
  static const int _frameSkipInterval = 3; // Process every Nth frame
  static const double _smoothingFactor = 0.3; // For exponential moving average
  List<double>? _smoothedScores;

  // For snapshot capture
  bool _isCapturing = false;

  final _classifier = FabricClassifierService.instance;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Pre-load the model
      await _classifier.ensureModelLoaded();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = 'No cameras found');
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Camera error: $e');
    }
  }

  void _processCameraFrame(CameraImage cameraImage) {
    // Skip frames to reduce processing load
    _frameSkipCount++;
    if (_frameSkipCount < _frameSkipInterval) return;
    _frameSkipCount = 0;

    // Don't process if already processing or capturing
    if (_isProcessingFrame || _isCapturing) return;
    _isProcessingFrame = true;

    // Run inference synchronously on this frame
    final result = _classifier.classifyCameraImage(cameraImage);

    if (result != null && mounted) {
      final scores = result.scores;

      // Initialize or update smoothed scores with exponential moving average
      if (_smoothedScores == null || _smoothedScores!.length != scores.length) {
        _smoothedScores = List<double>.from(scores);
      } else {
        for (int i = 0; i < scores.length; i++) {
          _smoothedScores![i] = _smoothingFactor * scores[i] +
              (1 - _smoothingFactor) * _smoothedScores![i];
        }
      }

      final smoothed = _smoothedScores!;

      // Find top index from smoothed scores
      int topIndex = 0;
      double topScore = smoothed[0];
      for (int i = 1; i < smoothed.length; i++) {
        if (smoothed[i] > topScore) {
          topScore = smoothed[i];
          topIndex = i;
        }
      }

      if (topScore < AppConfig.minConfidenceToAccept) {
        setState(() {
          _detectedClass = 'Ready to scan';
          _confidence = 0;
          _scores = [];
        });
      } else {
        final labels = _classifier.labels;
        final displayLabel = topIndex < labels.length
            ? _classifier.cleanLabel(labels[topIndex])
            : 'Unknown';

        setState(() {
          _detectedClass = displayLabel;
          _confidence = topScore * 100;
          _scores = smoothed;
        });
      }
    }

    _isProcessingFrame = false;
  }

  Future<void> _captureAndNavigate() async {
    if (_isCapturing || _cameraController == null || !_isCameraInitialized) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // Take picture
      final xFile = await _cameraController!.takePicture();
      final file = File(xFile.path);

      // Run inference on captured image for accurate result
      final result = await _classifier.classifyImage(file);

      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to classify image')),
        );
        setState(() => _isCapturing = false);
        return;
      }

      final labels = _classifier.labels;
      for (int i = 0; i < result.scores.length; i++) {
        final label = i < labels.length
            ? _classifier.cleanLabel(labels[i])
            : 'Class $i';
        debugPrint(
          '$i: $label -> ${result.scores[i].toStringAsFixed(3)}',
        );
      }

      if (result.topConfidence < AppConfig.minConfidenceToAccept) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No known fabric detected. Please ensure the fabric fills the frame and try again.',
            ),
          ),
        );
        setState(() {
          _isCapturing = false;
          _detectedClass = 'No fabric detected';
          _confidence = 0;
          _scores = [];
        });
        return;
      }

      final cleanLabel = _classifier.cleanLabel(result.topLabel);

      // Save detection record
      final groundTruthClass = widget.selectedClassName ?? 'Unknown';
      final groundTruthIndex = widget.selectedClassIndex ?? -1;

      final record = DetectionRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        groundTruthClass: groundTruthClass,
        groundTruthIndex: groundTruthIndex,
        predictedClass: cleanLabel,
        predictedIndex: result.topIndex,
        confidence: result.topConfidence,
        scores: result.scores,
      );

      await DetectionStorageService.instance.saveRecord(record);

      final selectedIndex = widget.selectedClassIndex ?? -1;
      // Only enforce mismatch warning when a specific fabric was chosen.
      if (selectedIndex != -1 && result.topIndex != selectedIndex) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Detected fabric does not match the selected class. Please retake with the correct fabric.',
            ),
          ),
        );
        setState(() {
          _isCapturing = false;
          _detectedClass = 'No fabric detected';
          _confidence = 0;
          _scores = [];
        });
        return;
      }

      // Update overlay with this result (shown when user comes back)
      setState(() {
        _detectedClass = cleanLabel;
        _confidence = result.topConfidence * 100;
        _scores = result.scores;
      });

      // Navigate to result page
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetectionResultPage(
            detectedClassName: cleanLabel,
            confidence: result.topConfidence * 100,
            scores: result.scores,
            recordId: record.id,
          ),
        ),
      );

      if (mounted) {
        setState(() => _isCapturing = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile == null) return;

      setState(() => _isCapturing = true);

      final imageFile = File(pickedFile.path);
      final result = await _classifier.classifyImage(imageFile);

      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to classify image')),
        );
        setState(() => _isCapturing = false);
        return;
      }

      if (result.topConfidence < AppConfig.minConfidenceToAccept) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No known fabric detected in the image. Please try another image.',
            ),
          ),
        );
        setState(() {
          _isCapturing = false;
          _detectedClass = 'No fabric detected';
          _confidence = 0;
          _scores = [];
        });
        return;
      }

      final cleanLabel = _classifier.cleanLabel(result.topLabel);

      // Save detection record
      final groundTruthClass = widget.selectedClassName ?? 'Unknown';
      final groundTruthIndex = widget.selectedClassIndex ?? -1;

      final record = DetectionRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        groundTruthClass: groundTruthClass,
        groundTruthIndex: groundTruthIndex,
        predictedClass: cleanLabel,
        predictedIndex: result.topIndex,
        confidence: result.topConfidence,
        scores: result.scores,
      );

      await DetectionStorageService.instance.saveRecord(record);

      final selectedIndex = widget.selectedClassIndex ?? -1;
      if (selectedIndex != -1 && result.topIndex != selectedIndex) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Detected fabric does not match the selected class. Please try another image.',
            ),
          ),
        );
        setState(() {
          _isCapturing = false;
          _detectedClass = 'No fabric detected';
          _confidence = 0;
          _scores = [];
        });
        return;
      }

      // Update overlay with this result
      setState(() {
        _detectedClass = cleanLabel;
        _confidence = result.topConfidence * 100;
        _scores = result.scores;
      });

      // Navigate to result page
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetectionResultPage(
            detectedClassName: cleanLabel,
            confidence: result.topConfidence * 100,
            scores: result.scores,
            recordId: record.id,
          ),
        ),
      );

      if (mounted) {
        setState(() => _isCapturing = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _isCapturing = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Color _getConfidenceColor() {
    if (_confidence >= 70) return Colors.green;
    if (_confidence >= 40) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        widget.selectedClassName ?? 'Any fabric';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Positioned.fill(
            child: _buildCameraPreview(),
          ),

          // Top bar with ground truth
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(displayName),
                const Spacer(),
                _buildDetectionOverlay(),
                _buildBottomControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Loading camera & model...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    // Edge‑to‑edge preview with a subtle vignette to make overlays readable.
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ??
                MediaQuery.of(context).size.width,
            height: _cameraController!.value.previewSize?.width ??
                MediaQuery.of(context).size.height,
            child: CameraPreview(_cameraController!),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withOpacity(0.55),
                Colors.transparent,
                Colors.black.withOpacity(0.35),
              ],
            ),
          ),
        ),
        // Soft focus frame for fabric area
        Align(
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 2,
              ),
            ),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(), // purely for sizing
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(String displayName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Column(
            children: [
              const Text(
                'Reference fabric',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.greenAccent),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionOverlay() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _detectedClass,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_scores.isNotEmpty && _confidence > 0) ...[
            // Confidence bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _confidence / 100,
                backgroundColor: Colors.white12,
                valueColor:
                    AlwaysStoppedAnimation<Color>(_getConfidenceColor()),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_confidence.toStringAsFixed(1)}% Confidence',
              style: TextStyle(
                color: _getConfidenceColor(),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Fill the frame with the fabric texture, then capture.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Gallery button
              ElevatedButton.icon(
                onPressed: _isCapturing ? null : _pickFromGallery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.08),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.photo_library_rounded, size: 20),
                label: const Text(
                  'Gallery',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 16),
              // Camera capture button
              Expanded(
                child: ElevatedButton(
                  onPressed: _isCapturing ? null : _captureAndNavigate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getConfidenceColor(),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    elevation: 6,
                    shadowColor: _getConfidenceColor().withOpacity(0.5),
                  ),
                  child: _isCapturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Scan fabric',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
