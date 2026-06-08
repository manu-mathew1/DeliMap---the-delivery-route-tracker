import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../db/database_helper.dart';
import '../models/package_item.dart';
import '../models/receiver_record.dart';
import '../services/geocoding_service.dart';
import 'ocr_scan_screen.dart';

enum ScanFeedbackType { success, duplicate, notFound }

class BarcodeScanScreen extends StatefulWidget {
  final String sessionId;
  const BarcodeScanScreen({Key? key, required this.sessionId}) : super(key: key);

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  CameraController? _cameraController;
  late final BarcodeScanner _barcodeScanner;
  bool _isPermissionGranted = false;
  bool _isProcessing = false;
  bool _flashOn = false;
  PackageType _manualPackageType = PackageType.delivery;

  @override
  void initState() {
    super.initState();
    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeScanner.close();
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

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      if (_flashOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
      } else {
        await _cameraController!.setFlashMode(FlashMode.torch);
      }
      setState(() {
        _flashOn = !_flashOn;
      });
    } catch (e) {
      print('Error setting flash mode: $e');
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
      final inputImage = InputImage.fromFilePath(image.path);
      final List<Barcode> barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No barcode or QR code detected. Align it inside the box.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Get the first barcode detected
      final Barcode barcode = barcodes.first;
      final String? barcodeValue = barcode.rawValue;

      if (barcodeValue == null || barcodeValue.isEmpty) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      await _handleScannedBarcode(barcodeValue);
    } catch (e) {
      print('Barcode scanning error: $e');
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan error: $e'),
            backgroundColor: const Color(0xFFFF453A),
          ),
        );
      }
    }
  }

  Future<void> _handleScannedBarcode(String barcodeValue) async {
    // 1. Check if this package is already in today's active session
    final List<PackageItem> activePackages = await DatabaseHelper.instance.getPackagesInSession(widget.sessionId);
    final PackageItem? existingPkg = activePackages.firstWhere(
      (p) => p.id == barcodeValue,
      orElse: () => null as dynamic,
    );

    if (existingPkg != null) {
      _playFeedback(ScanFeedbackType.success);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Scanned: ${existingPkg.name} (Stop already in runsheet)'),
            backgroundColor: const Color(0xFF30D158),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    // 2. Query receivers table in local SQLite (by barcode/AWB just in case)
    final ReceiverRecord? receiver = await DatabaseHelper.instance.getReceiver(barcodeValue);

    if (receiver == null) {
      _playFeedback(ScanFeedbackType.notFound);
      if (mounted) {
        _showNotFoundDialog(barcodeValue);
      }
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    // 4. Add package to local SQLite runsheet
    final newPkg = PackageItem(
      id: barcodeValue, // Use tracking ID as the package primary key
      sessionId: widget.sessionId,
      name: receiver.name,
      addressText: receiver.addressText,
      status: PackageStatus.pending,
      scannedAt: DateTime.now(),
      receiverId: receiver.id,
      latitude: receiver.latitude,
      longitude: receiver.longitude,
      notes: receiver.notes,
    );

    await DatabaseHelper.instance.insertPackage(newPkg);
    _playFeedback(ScanFeedbackType.success);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Added package for ${receiver.name}'),
          backgroundColor: const Color(0xFF30D158),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    setState(() {
      _isProcessing = false;
    });
  }

  Future<void> _playFeedback(ScanFeedbackType type) async {
    switch (type) {
      case ScanFeedbackType.success:
        await HapticFeedback.mediumImpact();
        break;
      case ScanFeedbackType.duplicate:
        await HapticFeedback.vibrate();
        break;
      case ScanFeedbackType.notFound:
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 150));
        await HapticFeedback.vibrate();
        break;
    }
  }

  void _showNotFoundDialog(String barcodeValue) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF453A), size: 24),
            SizedBox(width: 8),
            Text('AWB Not Found', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Tracking ID "$barcodeValue" was not found in the imported runsheet.\n\n'
          'What would you like to do?',
          style: const TextStyle(color: Color(0xFF8E8E93)),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Scan Label text (OCR)', style: TextStyle(color: Color(0xFFF5A623))),
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => OcrScanScreen(sessionId: widget.sessionId),
                ),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5A623)),
            child: const Text('Enter Manually', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              _showManualEntrySheet(barcodeValue);
            },
          ),
        ],
      ),
    );
  }

  void _showManualEntrySheet(String barcodeValue) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    bool isSaving = false;
    PackageType _manualPackageType = PackageType.delivery; // reset manual package type

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit, color: Color(0xFFF5A623), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Manual Entry: $barcodeValue',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('BUYER NAME', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  enabled: !isSaving,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
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
                  controller: addressController,
                  enabled: !isSaving,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    fillColor: const Color(0xFF2C2C2E),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('PACKAGE TYPE', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _manualPackageType = PackageType.delivery;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _manualPackageType == PackageType.delivery
                                ? const Color(0xFF0A84FF).withOpacity(0.15)
                                : const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _manualPackageType == PackageType.delivery
                                  ? const Color(0xFF0A84FF)
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'DELIVERY',
                              style: TextStyle(
                                color: _manualPackageType == PackageType.delivery
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
                          setModalState(() {
                            _manualPackageType = PackageType.pickup;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _manualPackageType == PackageType.pickup
                                ? const Color(0xFFBF5AF2).withOpacity(0.15)
                                : const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _manualPackageType == PackageType.pickup
                                  ? const Color(0xFFBF5AF2)
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'PICKUP',
                              style: TextStyle(
                                color: _manualPackageType == PackageType.pickup
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
                    onPressed: isSaving ? null : () async {
                      final nameText = nameController.text.trim();
                      final addressText = addressController.text.trim();

                      if (nameText.isEmpty || addressText.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Name and Address cannot be empty.')),
                        );
                        return;
                      }

                      setModalState(() {
                        isSaving = true;
                      });

                      try {
                        double? lat;
                        double? lng;
                        String? resolvedReceiverId;

                        // Geocode address
                        final geocodeResult = await GeocodingService.geocodeAddress(addressText);
                        if (geocodeResult != null) {
                          lat = geocodeResult.latitude;
                          lng = geocodeResult.longitude;

                          // Check proximity match in master database
                          final nearbyReceiver = await DatabaseHelper.instance.findNearbyReceiverMatch(
                            name: nameText,
                            latitude: lat,
                            longitude: lng,
                            maxDistanceMeters: 1000.0,
                            minNameSimilarity: 0.60,
                          );

                          if (nearbyReceiver != null) {
                            resolvedReceiverId = nearbyReceiver.id;
                            lat = nearbyReceiver.latitude;
                            lng = nearbyReceiver.longitude;
                            print('Manual Entry: Resolved $barcodeValue via proximity to master receiver: ${nearbyReceiver.name} ($lat, $lng)');
                          } else {
                            // Check proximity match in current session packages
                            final List<PackageItem> activePackages = await DatabaseHelper.instance.getPackagesInSession(widget.sessionId);
                            PackageItem? proximitySessionMatch;
                            double bestSessionSim = 0.0;
                            double closestSessionDist = double.maxFinite;

                            for (final p in activePackages) {
                              if (p.latitude != null && p.longitude != null && p.latitude != 0.0 && p.longitude != 0.0) {
                                final dist = DatabaseHelper.instance.calculateDistance(lat!, lng!, p.latitude!, p.longitude!);
                                if (dist <= 1000.0) {
                                  final nameSim = DatabaseHelper.instance.calculateNameSimilarity(nameText, p.name);
                                  if (nameSim >= 0.60) {
                                    if (nameSim > bestSessionSim) {
                                      bestSessionSim = nameSim;
                                      proximitySessionMatch = p;
                                      closestSessionDist = dist;
                                    } else if (nameSim == bestSessionSim) {
                                      if (dist < closestSessionDist) {
                                        proximitySessionMatch = p;
                                        closestSessionDist = dist;
                                      }
                                    }
                                  }
                                }
                              }
                            }

                            if (proximitySessionMatch != null) {
                              resolvedReceiverId = proximitySessionMatch.receiverId;
                              lat = proximitySessionMatch.latitude;
                              lng = proximitySessionMatch.longitude;
                              print('Manual Entry: Grouping $barcodeValue with session package ${proximitySessionMatch.name} via proximity ($closestSessionDist meters)');
                            } else {
                              resolvedReceiverId = barcodeValue;
                            }
                          }
                        } else {
                          lat = 0.0;
                          lng = 0.0;
                          resolvedReceiverId = barcodeValue;
                        }

                        final newPkg = PackageItem(
                          id: barcodeValue, // Use tracking AWB ID as key
                          sessionId: widget.sessionId,
                          name: nameText,
                          addressText: addressText,
                          status: PackageStatus.pending,
                          scannedAt: DateTime.now(),
                          receiverId: resolvedReceiverId,
                          latitude: lat,
                          longitude: lng,
                          notes: 'Manually Entered',
                          type: _manualPackageType,
                        );

                        await DatabaseHelper.instance.insertPackage(newPkg);
                        Navigator.pop(context); // Pop sheet

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Added package manually.'),
                            backgroundColor: Color(0xFF30D158),
                          ),
                        );
                      } catch (e) {
                        print('Manual Entry Error: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error saving package: $e'),
                            backgroundColor: const Color(0xFFFF453A),
                          ),
                        );
                      } finally {
                        setModalState(() {
                          isSaving = false;
                        });
                      }
                    },
                    child: isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'CONFIRM & SAVE',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
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
        title: const Text('Scan Package Barcode', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: const Color(0xFFF5A623)),
            onPressed: _toggleFlash,
          ),
        ],
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
                    : const Icon(Icons.qr_code_scanner, color: Colors.black, size: 28),
              ),
            ),
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
              width: 320,
              height: 160,
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
                'ALIGN AWB BARCODE OR QR CODE INSIDE BOX',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
