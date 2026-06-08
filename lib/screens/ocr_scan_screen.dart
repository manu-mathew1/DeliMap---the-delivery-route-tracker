import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../db/database_helper.dart';
import '../models/package_item.dart';
import '../models/receiver_record.dart';
import '../services/geocoding_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';

class OcrScanScreen extends StatefulWidget {
  final String sessionId;
  const OcrScanScreen({Key? key, required this.sessionId}) : super(key: key);

  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> {
  CameraController? _cameraController;
  late final TextRecognizer _textRecognizer;
  bool _isPermissionGranted = false;
  bool _isProcessing = false;
  bool _showConfirmCard = false;
  PackageType _ocrPackageType = PackageType.delivery;

  final TextEditingController _nameEditController = TextEditingController();
  final TextEditingController _addressEditController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    _nameEditController.dispose();
    _addressEditController.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      print('No cameras available.');
      return;
    }

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isPermissionGranted = true;
        });
      }
    } catch (e) {
      print('Camera initialization error: $e');
    }
  }

  Future<void> _captureAndProcess() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile image = await _cameraController!.takePicture();
      
      // Get image dimensions dynamically to map the physical guide box
      final bytes = await image.readAsBytes();
      final sizeResult = _getJpegSize(bytes);
      int imageWidth;
      int imageHeight;
      if (sizeResult != null) {
        imageWidth = sizeResult.width;
        imageHeight = sizeResult.height;
      } else {
        final decodedImage = await decodeImageFromList(bytes);
        imageWidth = decodedImage.width;
        imageHeight = decodedImage.height;
      }

      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // Get the viewport size to determine percentages of guide box (300 width, 200 height)
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      final double viewportWidth = renderBox?.size.width ?? 375.0;
      final double viewportHeight = renderBox?.size.height ?? 812.0;

      const double boxW = 300.0;
      const double boxH = 200.0;

      final double leftPercent = (viewportWidth - boxW) / 2 / viewportWidth;
      final double rightPercent = (viewportWidth + boxW) / 2 / viewportWidth;
      final double topPercent = (viewportHeight - boxH) / 2 / viewportHeight;
      final double bottomPercent = (viewportHeight + boxH) / 2 / viewportHeight;

      // ML Kit processes image in upright portrait orientation due to EXIF rotation
      final double mlWidth = (imageWidth < imageHeight ? imageWidth : imageHeight).toDouble();
      final double mlHeight = (imageWidth > imageHeight ? imageWidth : imageHeight).toDouble();

      final double leftLimit = mlWidth * leftPercent;
      final double rightLimit = mlWidth * rightPercent;
      final double topLimit = mlHeight * topPercent;
      final double bottomLimit = mlHeight * bottomPercent;

      final List<TextBlock> filteredBlocks = [];
      for (TextBlock block in recognizedText.blocks) {
        final rect = block.boundingBox;
        final blockCenterX = rect.left + rect.width / 2;
        final blockCenterY = rect.top + rect.height / 2;

        if (blockCenterX >= leftLimit && blockCenterX <= rightLimit &&
            blockCenterY >= topLimit && blockCenterY <= bottomLimit) {
          filteredBlocks.add(block);
        }
      }

      // Sort text blocks top-to-bottom so we get Name first, then Address
      filteredBlocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

      _parseFilteredText(filteredBlocks);
    } catch (e) {
      print('Text recognition error: $e');
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: const Color(0xFFFF453A),
          ),
        );
      }
    }
  }

  void _parseFilteredText(List<TextBlock> blocks) {
    if (blocks.isEmpty) {
      setState(() {
        _nameEditController.text = '';
        _addressEditController.text = '';
        _showConfirmCard = true;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No text detected. You can enter details manually.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    String name = 'Unknown Receiver';
    String address = '';

    // First block contains the Name, subsequent blocks contain the Address
    name = blocks.first.text.trim();
    if (blocks.length > 1) {
      address = blocks.sublist(1).map((b) => b.text.trim()).join(', ');
    }

    // Clean address of return garbage labels
    address = address.replaceAll(RegExp(r'(if undelivered|please return to|seller details).*', caseSensitive: false), '').trim();

    setState(() {
      _nameEditController.text = name;
      _addressEditController.text = address;
      _showConfirmCard = true;
      _isProcessing = false;
    });
  }

  Future<void> _confirmPackage() async {
    final nameText = _nameEditController.text.trim();
    final addressText = _addressEditController.text.trim();

    if (nameText.isEmpty || addressText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and Address cannot be empty.')),
      );
      return;
    }

    final newPkg = PackageItem(
      id: const Uuid().v4(),
      sessionId: widget.sessionId,
      name: nameText,
      addressText: addressText,
      status: PackageStatus.pending,
      scannedAt: DateTime.now(),
      notes: '',
      type: _ocrPackageType,
    );

    // Insert package into SQLite database
    await DatabaseHelper.instance.insertPackage(newPkg);

    // Start background processing: Query database & Google Geocoding API
    _startBackgroundResolve(newPkg);

    setState(() {
      _showConfirmCard = false;
      _ocrPackageType = PackageType.delivery;
      _nameEditController.clear();
      _addressEditController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to runsheet. Ready for next package.'), duration: Duration(milliseconds: 800)),
    );
  }

  double _calculateStringSimilarity(String s1, String s2) {
    final clean1 = s1.trim().toLowerCase();
    final clean2 = s2.trim().toLowerCase();

    if (clean1 == clean2) return 1.0;
    if (clean1.isEmpty || clean2.isEmpty) return 0.0;

    final List<int> d = List<int>.filled((clean1.length + 1) * (clean2.length + 1), 0);

    for (int i = 0; i <= clean1.length; i++) {
      d[i * (clean2.length + 1)] = i;
    }
    for (int j = 0; j <= clean2.length; j++) {
      d[j] = j;
    }

    for (int i = 1; i <= clean1.length; i++) {
      for (int j = 1; j <= clean2.length; j++) {
        final int cost = clean1[i - 1] == clean2[j - 1] ? 0 : 1;
        d[i * (clean2.length + 1) + j] = [
          d[(i - 1) * (clean2.length + 1) + j] + 1, // deletion
          d[i * (clean2.length + 1) + j - 1] + 1, // insertion
          d[(i - 1) * (clean2.length + 1) + j - 1] + cost // substitution
        ].reduce((curr, next) => curr < next ? curr : next);
      }
    }

    final distance = d[clean1.length * (clean2.length + 1) + clean2.length];
    final maxLength = clean1.length > clean2.length ? clean1.length : clean2.length;
    return 1.0 - (distance / maxLength);
  }

  // Background resolving queue
  Future<void> _startBackgroundResolve(PackageItem package) async {
    // 1. Check SQLite for name match and similar address (Fuzzy Match >= 80%)
    final candidateReceivers = await DatabaseHelper.instance.getReceiversByName(package.name);
    
    ReceiverRecord? bestMatch;
    double highestSimilarity = 0.0;

    for (final receiver in candidateReceivers) {
      final similarity = _calculateStringSimilarity(package.addressText, receiver.addressText);
      if (similarity >= 0.80 && similarity > highestSimilarity) {
        highestSimilarity = similarity;
        bestMatch = receiver;
      }
    }

    if (bestMatch != null) {
      // Fuzzy/Exact Match found! Save and update package stop
      final updatedPkg = package.copyWith(
        receiverId: bestMatch.id,
        latitude: bestMatch.latitude,
        longitude: bestMatch.longitude,
        notes: bestMatch.notes,
      );
      await DatabaseHelper.instance.updatePackage(updatedPkg);
      print('Background Resolve: Match found in DB for ${package.name} (Similarity: ${(highestSimilarity * 100).toStringAsFixed(1)}%). Exact coordinates mapped.');
      return;
    }

    // 2. Check for similar addresses in SQLite database to establish a geocoding bias (Fuzzy Match)
    double? biasLat;
    double? biasLng;
    final similarList = await DatabaseHelper.instance.findSimilarReceivers(package.addressText, threshold: 0.5);
    if (similarList.isNotEmpty) {
      final bestMatch = similarList.first.key;
      biasLat = bestMatch.latitude;
      biasLng = bestMatch.longitude;
      print('Background Resolve: Similar address found (${similarList.first.value * 100}% similarity). Injecting coordinate bias: $biasLat, $biasLng');
    }

    // 3. Call Google Geocoding API with bias
    final geocodeResult = await GeocodingService.geocodeAddress(
      package.addressText,
      biasLatitude: biasLat,
      biasLongitude: biasLng,
    );

    if (geocodeResult != null) {
      final updatedPkg = package.copyWith(
        latitude: geocodeResult.latitude,
        longitude: geocodeResult.longitude,
      );
      await DatabaseHelper.instance.updatePackage(updatedPkg);
      print('Background Resolve: Google Geocoded successfully for ${package.name}: ${geocodeResult.latitude}, ${geocodeResult.longitude}');
    } else {
      print('Background Resolve: Geocoding failed for ${package.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPermissionGranted || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt_outlined, color: Color(0xFFF5A623), size: 48),
              SizedBox(height: 16),
              Text('Accessing camera preview...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Package Label', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 1. Camera Viewport
          Positioned.fill(
            child: CameraPreview(_cameraController!),
          ),
          // 2. Frame Overlay box guide
          Positioned.fill(
            child: _buildFrameOverlay(),
          ),
          // 3. Capture Trigger Button
          if (!_showConfirmCard)
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFFF5A623),
                  onPressed: _captureAndProcess,
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Icon(Icons.photo_camera, color: Colors.black, size: 28),
                ),
              ),
            ),
          // 4. Confirm Result Sheet Card
          if (_showConfirmCard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildConfirmCard(),
            ),
        ],
      ),
    );
  }

  Widget _buildFrameOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.4),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 300,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFF5A623), width: 3),
                borderRadius: BorderRadius.circular(16),
                color: Colors.transparent,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'ALIGN BUYER NAME & ADDRESS INSIDE BOX',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmCard() {
    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note_outlined, color: Color(0xFFF5A623), size: 24),
              SizedBox(width: 8),
              Text(
                'Confirm & Edit Scan Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_nameEditController.text.isEmpty && _addressEditController.text.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9F0A).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF9F0A), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9F0A), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not automatically read name & address. You can type them manually below.',
                      style: TextStyle(color: Color(0xFFFF9F0A), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Text('BUYER NAME', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameEditController,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              fillColor: const Color(0xFF2C2C2E),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 16),
          const Text('DELIVERY ADDRESS', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _addressEditController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              fillColor: const Color(0xFF2C2C2E),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const Text('PACKAGE TYPE', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _ocrPackageType = PackageType.delivery;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _ocrPackageType == PackageType.delivery
                          ? const Color(0xFF0A84FF).withOpacity(0.15)
                          : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _ocrPackageType == PackageType.delivery
                            ? const Color(0xFF0A84FF)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'DELIVERY',
                        style: TextStyle(
                          color: _ocrPackageType == PackageType.delivery
                              ? const Color(0xFF0A84FF)
                              : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _ocrPackageType = PackageType.pickup;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _ocrPackageType == PackageType.pickup
                          ? const Color(0xFFBF5AF2).withOpacity(0.15)
                          : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _ocrPackageType == PackageType.pickup
                            ? const Color(0xFFBF5AF2)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'PICKUP',
                        style: TextStyle(
                          color: _ocrPackageType == PackageType.pickup
                              ? const Color(0xFFBF5AF2)
                              : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: _confirmPackage,
              child: const Text(
                '✅  CONFIRM & SCAN NEXT',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showConfirmCard = false;
                });
              },
              child: const Text('Rescan Label', style: TextStyle(color: Color(0xFFFF453A))),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSize {
  final int width;
  final int height;
  _ImageSize(this.width, this.height);
}

_ImageSize? _getJpegSize(Uint8List bytes) {
  if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  int i = 2;
  while (i < bytes.length - 8) {
    if (bytes[i] == 0xFF) {
      final marker = bytes[i + 1];
      if (marker == 0x00 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (marker == 0xD9) {
        break; // EOI
      }
      if ((marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7) ||
          (marker >= 0xC9 && marker <= 0xCB) ||
          (marker >= 0xCD && marker <= 0xCF)) {
        final height = (bytes[i + 5] << 8) | bytes[i + 6];
        final width = (bytes[i + 7] << 8) | bytes[i + 8];
        return _ImageSize(width, height);
      }
      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + length;
    } else {
      i++;
    }
  }
  return null;
}
