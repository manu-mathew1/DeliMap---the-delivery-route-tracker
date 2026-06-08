import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/delivery_session.dart';
import '../models/package_item.dart';
import '../models/receiver_record.dart';
import '../models/delivery_stop.dart';
import 'ocr_scan_screen.dart';
import 'barcode_scan_screen.dart';
import '../services/import_service.dart';
import 'route_map_screen.dart';
import 'packing_order_screen.dart';
import 'receivers_book_screen.dart';
import 'settings_screen.dart';
import '../services/route_service.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  DeliverySession? _activeSession;
  List<PackageItem> _packages = [];
  List<DeliveryStop> _stops = [];
  List<DeliverySession> _pastSessions = [];
  bool _isLoading = true;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    setState(() => _isLoading = true);
    final active = await DatabaseHelper.instance.getActiveSession();
    final past = await DatabaseHelper.instance.getAllSessions();
    
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      print('Queue GPS fetch error: $e');
    }

    List<PackageItem> pkgs = [];
    List<DeliveryStop> stops = [];
    if (active != null) {
      pkgs = await DatabaseHelper.instance.getPackagesInSession(active.id);
      stops = RouteService.groupPackagesIntoStops(pkgs);
    }

    setState(() {
      _activeSession = active;
      _packages = pkgs;
      _stops = stops;
      _pastSessions = past.where((s) => s.status == SessionStatus.completed).toList();
      _isLoading = false;
    });
  }

  Future<void> _importRunsheetPDF() async {
    if (_activeSession == null) return;
    try {
      final records = await ImportService.pickAndParsePDF();
      if (records == null) return; // Cancelled

      // Check how many records actually need geocoding (are not duplicates in session and not in master directory)
      int newCount = 0;
      final Set<String> existingPackageIds = _packages.map((p) => p.id).toSet();

      for (final r in records) {
        final String trackingId = r['id'] as String;
        final String name = r['name'] as String;
        final String address = r['addressText'] as String;

        if (!existingPackageIds.contains(trackingId)) {
          // Check if it exists in the master directory
          var existingReceiver = await DatabaseHelper.instance.getReceiverByNameAndAddress(name, address);
          if (existingReceiver == null) {
            existingReceiver = await DatabaseHelper.instance.getReceiver(trackingId);
          }
          if (existingReceiver == null) {
            newCount++;
          }
        }
      }

      if (newCount > 10) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text('Confirm Geocoding', style: TextStyle(color: Colors.white)),
            content: Text(
              'There are $newCount new stops in this runsheet that will be geocoded using the Google Geocoding API. '
              'This may take some time and consume API quota. Proceed?',
              style: const TextStyle(color: Color(0xFF8E8E93)),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
                onPressed: () => Navigator.pop(context, false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5A623)),
                child: const Text('Proceed', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }

      // Show progress overlay
      double progress = 0.0;
      String status = "Initializing import...";
      StateSetter? dialogSetState;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                dialogSetState = setDialogState;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Importing Daily Runsheet',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: progress,
                      color: const Color(0xFFF5A623),
                      backgroundColor: const Color(0xFF2C2C2E),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );

      try {
        final result = await ImportService.processPDFRunsheetImport(
          sessionId: _activeSession!.id,
          records: records,
          onProgress: (newStatus, newProgress) {
            if (dialogSetState != null) {
              dialogSetState!(() {
                status = newStatus;
                progress = newProgress;
              });
            }
          },
        );

        Navigator.pop(context); // Dismiss progress dialog
        _loadSessionData();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Runsheet loaded! Added ${result.importedCount} packages, '
              'skipped ${result.duplicateCount} duplicates, '
              'errors: ${result.errorCount}.',
            ),
            backgroundColor: const Color(0xFF30D158),
          ),
        );
      } catch (e) {
        Navigator.pop(context); // Dismiss progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: const Color(0xFFFF453A),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to parse PDF: $e'),
          backgroundColor: const Color(0xFFFF453A),
        ),
      );
    }
  }

  Future<void> _startNewDay() async {
    final newSession = DeliverySession(
      id: const Uuid().v4(),
      date: DateTime.now(),
      status: SessionStatus.active,
    );
    await DatabaseHelper.instance.insertSession(newSession);
    await _loadSessionData();
  }

  Future<void> _endDay() async {
    if (_activeSession == null) return;
    
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('End Delivery Day?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to end today\'s session? This will lock the runsheet and archive it.',
          style: TextStyle(color: Color(0xFF8E8E93)),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
            child: const Text('End Session'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updated = _activeSession!.copyWith(status: SessionStatus.completed);
      await DatabaseHelper.instance.updateSession(updated);
      await DatabaseHelper.instance.prunePastSessions(15);
      await _loadSessionData();
    }
  }

  // Refresh page data when returning from screens
  void _onDataChanged() {
    _loadSessionData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFF5A623))),
      );
    }

    final List<Widget> screens = [
      _buildDashboardTab(),
      _buildQueueTab(),
      RouteMapScreen(activeSession: _activeSession, onDataChanged: _onDataChanged),
      const ReceiversBookScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(child: screens[_currentTab]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() {
            _currentTab = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1C1C1E),
        selectedItemColor: const Color(0xFFF5A623),
        unselectedItemColor: const Color(0xFF8E8E93),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: 'Queue'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Route'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Receivers'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    if (_activeSession == null) {
      return _buildNoActiveSessionView();
    }
    return _buildActiveSessionView();
  }

  Widget _buildNoActiveSessionView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Good Morning, Agent',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(DateTime.now()),
            style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
          ),
          const Spacer(flex: 2),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1C1C1E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No active session',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ready to start your delivery day?',
                  style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              onPressed: _startNewDay,
              child: const Text(
                '➕  START NEW DAY',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            '─────  Recent Sessions  ─────',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93), letterSpacing: 1.0),
          ),
          const SizedBox(height: 16),
          Expanded(
            flex: 3,
            child: _pastSessions.isEmpty
                ? const Center(
                    child: Text('No past sessions recorded yet.', style: TextStyle(color: Color(0xFF8E8E93))),
                  )
                : ListView.builder(
                    itemCount: _pastSessions.length,
                    itemBuilder: (context, index) {
                      final session = _pastSessions[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final pkgs = await DatabaseHelper.instance.getPackagesInSession(session.id);
                              if (mounted) {
                                _showSessionSummaryBottomSheet(session, pkgs);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDate(session.date),
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text('Status: Completed', style: TextStyle(color: Color(0xFF30D158), fontSize: 12)),
                                    ],
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF8E8E93)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionView() {
    final total = _packages.length;
    final done = _packages.where((p) => p.status == PackageStatus.delivered).length;
    final left = total - done;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DeliMap Dashboard', style: TextStyle(fontSize: 18, color: Color(0xFF8E8E93))),
                  Text(_formatDate(_activeSession!.date), style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              TextButton(
                onPressed: _endDay,
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF453A)),
                child: const Text('End Day', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Statistics Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('📦 Total', '$total'),
                _buildStatItem('✅ Done', '$done'),
                _buildStatItem('⏳ Left', '$left'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Action Buttons
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.black),
              label: const Text('📋 IMPORT DAILY RUNSHEET PDF', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              onPressed: _importRunsheetPDF,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.black),
              label: const Text('📷 SCAN AWB BARCODES', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BarcodeScanScreen(sessionId: _activeSession!.id),
                  ),
                );
                _loadSessionData(); // reload on return
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.text_fields, color: Color(0xFFF5A623)),
              label: const Text('📷 SCAN LABEL TEXT (OCR)', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFF5A623)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OcrScanScreen(sessionId: _activeSession!.id),
                  ),
                );
                _loadSessionData(); // reload on return
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined, color: Color(0xFFF5A623)),
                    label: const Text('🗺️ VERIFY ROUTE', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFF5A623)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentTab = 1; // Switch to Map Tab
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.backpack_outlined, color: Color(0xFFF5A623)),
                    label: const Text('🎒 PACK BAG', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFF5A623)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PackingOrderScreen(packages: _packages),
                        ),
                      );
                      _loadSessionData();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            '─────  Today\'s Stops  ─────',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93), letterSpacing: 1.0),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _stops.isEmpty
                ? const Center(
                    child: Text('Scan package labels to populate runsheet.', style: TextStyle(color: Color(0xFF8E8E93))),
                  )
                : ListView.builder(
                    itemCount: _stops.length,
                    itemBuilder: (context, index) {
                      final stop = _stops[index];
                      final pkgCountText = stop.packages.length > 1 ? ' (${stop.packages.length} pkg)' : '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF2C2C2E),
                              foregroundColor: const Color(0xFFF5A623),
                              child: Text('${index + 1}'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${stop.name}$pkgCountText', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Text(stop.addressText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStopTypeBadge(stop),
                            const SizedBox(width: 8),
                            _buildStopStatusBadge(stop),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopTypeBadge(DeliveryStop stop) {
    final hasDelivery = stop.packages.any((p) => p.type == PackageType.delivery);
    final hasPickup = stop.packages.any((p) => p.type == PackageType.pickup);

    Color color;
    String label;
    IconData icon;

    if (hasDelivery && hasPickup) {
      color = const Color(0xFFFF9F0A); // Orange
      label = 'MIXED';
      icon = Icons.swap_horiz_rounded;
    } else if (hasPickup) {
      color = const Color(0xFFBF5AF2); // Purple
      label = 'PICKUP';
      icon = Icons.call_received_rounded;
    } else {
      color = const Color(0xFF0A84FF); // Blue
      label = 'DELIVERY';
      icon = Icons.local_shipping_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStopStatusBadge(DeliveryStop stop) {
    Color color = const Color(0xFF8E8E93);
    String label = 'Processing';

    if (stop.isDelivered) {
      color = const Color(0xFF30D158);
      label = 'Delivered';
    } else if (stop.isFailed) {
      color = const Color(0xFFFF453A);
      label = 'Failed';
    } else {
      if (stop.latitude == null) {
        color = const Color(0xFF8E8E93);
        label = '⏳ Geocoding';
      } else if (stop.packages.any((p) => p.receiverId != null)) {
        color = const Color(0xFF30D158);
        label = '✅ Known';
      } else {
        color = const Color(0xFFFF9F0A);
        label = '🆕 New';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
      ],
    );
  }

  Widget _buildQueueTab() {
    if (_activeSession == null) {
      return const Center(
        child: Text('No active delivery session.', style: TextStyle(color: Color(0xFF8E8E93))),
      );
    }

    final pending = _packages.where((p) => p.status == PackageStatus.pending).toList();
    final completed = _packages.where((p) => p.status == PackageStatus.delivered || p.status == PackageStatus.failed).toList();

    final pendingStops = RouteService.groupPackagesIntoStops(pending);
    final completedStops = RouteService.groupPackagesIntoStops(completed);

    completedStops.sort((a, b) {
      final aTime = a.packages.first.deliveredAt ?? a.packages.first.scannedAt;
      final bTime = b.packages.first.deliveredAt ?? b.packages.first.scannedAt;
      return bTime.compareTo(aTime);
    });

    double startLat = _currentPosition?.latitude ?? 9.5564;
    double startLng = _currentPosition?.longitude ?? 76.7871;

    final sortedPendingStops = RouteService.optimizeRoute(
      startLatitude: startLat,
      startLongitude: startLng,
      stops: pendingStops,
    );

    final List<DeliveryStop> sortedQueue = [...sortedPendingStops, ...completedStops];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Delivery Queue', style: TextStyle(fontSize: 18, color: Color(0xFF8E8E93))),
                  const SizedBox(height: 4),
                  Text(
                    '${sortedPendingStops.length} stops pending • ${completedStops.length} stops completed',
                    style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFFF5A623)),
                onPressed: _loadSessionData,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: sortedQueue.isEmpty
                ? const Center(
                    child: Text('Scan package labels to populate queue.', style: TextStyle(color: Color(0xFF8E8E93))),
                  )
                : ListView.builder(
                    itemCount: sortedQueue.length,
                    itemBuilder: (context, index) {
                      final stop = sortedQueue[index];
                      final isPending = stop.isPending;
                      final isDelivered = stop.isDelivered;
                      
                      final pendingIndex = sortedPendingStops.indexOf(stop);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(16),
                          border: isPending && pendingIndex == 0
                              ? Border.all(color: const Color(0xFFF5A623), width: 1.5)
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isPending
                                      ? (pendingIndex == 0 ? const Color(0xFFF5A623) : const Color(0xFF2C2C2E))
                                      : (isDelivered ? const Color(0xFF30D158).withOpacity(0.2) : const Color(0xFFFF453A).withOpacity(0.2)),
                                  foregroundColor: isPending
                                      ? (pendingIndex == 0 ? Colors.black : const Color(0xFFF5A623))
                                      : (isDelivered ? const Color(0xFF30D158) : const Color(0xFFFF453A)),
                                  child: isPending
                                      ? Text('${pendingIndex + 1}')
                                      : Icon(isDelivered ? Icons.check : Icons.close, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              stop.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                fontSize: 16,
                                                decoration: isPending ? null : TextDecoration.lineThrough,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _buildStopTypeBadge(stop),
                                          const SizedBox(width: 8),
                                          if (stop.packages.length > 1) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5A623).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFFF5A623), width: 0.5),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.inventory_2_outlined, color: Color(0xFFF5A623), size: 10),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${stop.packages.length} Pkgs',
                                                    style: const TextStyle(color: Color(0xFFF5A623), fontSize: 9, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          if (isPending && pendingIndex == 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5A623).withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'NEXT STOP',
                                                style: TextStyle(color: Color(0xFFF5A623), fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        stop.addressText,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                                      ),
                                      if (stop.packages.length > 1) ...[
                                        const SizedBox(height: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: stop.packages.map((pkg) {
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.qr_code_2_rounded, size: 14, color: Color(0xFF8E8E93)),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    pkg.id,
                                                    style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93), fontFamily: 'monospace'),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: pkg.status == PackageStatus.delivered
                                                          ? const Color(0xFF30D158).withOpacity(0.15)
                                                          : pkg.status == PackageStatus.failed
                                                              ? const Color(0xFFFF453A).withOpacity(0.15)
                                                              : const Color(0xFFF5A623).withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(3),
                                                    ),
                                                    child: Text(
                                                      pkg.status.name.toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        fontWeight: FontWeight.bold,
                                                        color: pkg.status == PackageStatus.delivered
                                                            ? const Color(0xFF30D158)
                                                            : pkg.status == PackageStatus.failed
                                                                ? const Color(0xFFFF453A)
                                                                : const Color(0xFFF5A623),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: pkg.type == PackageType.pickup
                                                          ? const Color(0xFFBF5AF2).withOpacity(0.15)
                                                          : const Color(0xFF0A84FF).withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(3),
                                                    ),
                                                    child: Text(
                                                      pkg.type.name.toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        fontWeight: FontWeight.bold,
                                                        color: pkg.type == PackageType.pickup
                                                            ? const Color(0xFFBF5AF2)
                                                            : const Color(0xFF0A84FF),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (stop.combinedNotes.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C2C2E),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '📝 ${stop.combinedNotes}',
                                  style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                            if (isPending) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.navigation_outlined, size: 16),
                                      label: const Text('NAVIGATE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFF5A623),
                                        side: const BorderSide(color: Color(0xFFF5A623)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                      onPressed: () => _launchNavigation(stop),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.check, size: 16, color: Colors.black),
                                      label: const Text('DELIVER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF30D158),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                      onPressed: () => _markDeliveredInQueue(stop),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Color(0xFFFF453A)),
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF453A).withOpacity(0.15),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    onPressed: () => _markFailedInQueue(stop),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isDelivered ? '✓ Delivered' : '✗ Failed',
                                    style: TextStyle(
                                      color: isDelivered ? const Color(0xFF30D158) : const Color(0xFFFF453A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton(
                                    child: const Text('Undo', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                                    onPressed: () async {
                                      for (final pkg in stop.packages) {
                                        final resetPkg = pkg.copyWith(
                                          status: PackageStatus.pending,
                                          deliveredAt: null,
                                        );
                                        await DatabaseHelper.instance.updatePackage(resetPkg);
                                      }
                                      _loadSessionData();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _markDeliveredInQueue(DeliveryStop stop) async {
    bool locationCorrect = true;
    final notesController = TextEditingController(text: stop.combinedNotes);

    final pendingCount = stop.packages.where((p) => p.status == PackageStatus.pending).length;
    final countText = pendingCount > 1 ? ' ($pendingCount packages)' : '';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: Text('✅ Confirm Delivery$countText', style: const TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(stop.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(stop.addressText, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                  const SizedBox(height: 16),
                  const Text('Was this the correct location?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  RadioListTile<bool>(
                    title: const Text('Yes, correct spot', style: TextStyle(color: Colors.white)),
                    value: true,
                    groupValue: locationCorrect,
                    activeColor: const Color(0xFFF5A623),
                    onChanged: (val) => setDialogState(() => locationCorrect = val!),
                  ),
                  RadioListTile<bool>(
                    title: const Text('No, update coordinates', style: TextStyle(color: Colors.white)),
                    value: false,
                    groupValue: locationCorrect,
                    activeColor: const Color(0xFFF5A623),
                    onChanged: (val) => setDialogState(() => locationCorrect = val!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Delivery Notes (optional)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      fillColor: const Color(0xFF2C2C2E),
                      filled: true,
                      hintText: 'e.g. blue gate, ring twice',
                      hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5A623)),
                child: const Text('Confirm', style: TextStyle(color: Colors.black)),
                onPressed: () async {
                  double lat = stop.latitude ?? 0.0;
                  double lng = stop.longitude ?? 0.0;

                  if (!locationCorrect) {
                    try {
                      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
                      lat = pos.latitude;
                      lng = pos.longitude;
                    } catch (e) {
                      print('Queue mark delivered GPS error: $e');
                    }
                  }

                  final String? firstReceiverId = stop.packages
                      .firstWhere((p) => p.receiverId != null, orElse: () => stop.packages.first)
                      .receiverId;

                  ReceiverRecord? existingReceiver;
                  if (firstReceiverId != null) {
                    existingReceiver = await DatabaseHelper.instance.getReceiver(firstReceiverId);
                  }
                  if (existingReceiver == null) {
                    existingReceiver = await DatabaseHelper.instance.getReceiverByNameAndAddress(stop.name, stop.addressText);
                  }

                  final int existingCount = existingReceiver?.deliveryCount ?? 0;
                  final String resolvedId = existingReceiver?.id ?? firstReceiverId ?? const Uuid().v4();

                  final receiverRecord = ReceiverRecord(
                    id: resolvedId,
                    name: stop.name,
                    addressText: stop.addressText,
                    latitude: lat,
                    longitude: lng,
                    notes: notesController.text,
                    deliveryCount: existingCount + stop.packages.length,
                    lastDelivered: DateTime.now(),
                    isVerified: true,
                  );

                  await DatabaseHelper.instance.insertReceiver(receiverRecord);

                  for (final pkg in stop.packages) {
                    if (pkg.status == PackageStatus.pending) {
                      final updatedPkg = pkg.copyWith(
                        status: PackageStatus.delivered,
                        deliveredAt: DateTime.now(),
                        receiverId: receiverRecord.id,
                        latitude: lat,
                        longitude: lng,
                        notes: notesController.text,
                      );
                      await DatabaseHelper.instance.updatePackage(updatedPkg);
                    }
                  }

                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (confirm == true) {
      _loadSessionData();
    }
  }

  Future<void> _markFailedInQueue(DeliveryStop stop) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('❌ Mark Delivery Failed', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to mark ${stop.packages.length > 1 ? "all packages at this stop" : "this package"} as delivery failed?'),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
            child: const Text('Yes, Failed'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final pkg in stop.packages) {
        if (pkg.status == PackageStatus.pending) {
          final updatedPkg = pkg.copyWith(
            status: PackageStatus.failed,
            deliveredAt: DateTime.now(),
          );
          await DatabaseHelper.instance.updatePackage(updatedPkg);
        }
      }
      _loadSessionData();
    }
  }

  Future<void> _launchNavigation(DeliveryStop stop) async {
    if (stop.latitude == null || stop.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot navigate: Stop is not geocoded yet.')),
      );
      return;
    }
    
    final googleMapsUrl = Uri.parse('google.navigation:q=${stop.latitude},${stop.longitude}&mode=d');
    final appleMapsUrl = Uri.parse('http://maps.apple.com/?daddr=${stop.latitude},${stop.longitude}');

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl);
    } else if (await canLaunchUrl(appleMapsUrl)) {
      await launchUrl(appleMapsUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch navigation application.')),
      );
    }
  }

  void _showSessionSummaryBottomSheet(DeliverySession session, List<PackageItem> packages) {
    final stops = RouteService.groupPackagesIntoStops(packages);
    
    final totalPackages = packages.length;
    final deliveredPackages = packages.where((p) => p.status == PackageStatus.delivered).length;
    final failedPackages = packages.where((p) => p.status == PackageStatus.failed).length;
    final pendingPackages = packages.where((p) => p.status == PackageStatus.pending).length;

    final totalStops = stops.length;
    final deliveredStops = stops.where((s) => s.isDelivered).length;

    double completionRate = totalPackages > 0 ? (deliveredPackages / totalPackages) * 100 : 0.0;

    // Calculate total COD Amount
    double totalCodAmount = 0.0;
    for (final pkg in packages) {
      if (pkg.status == PackageStatus.delivered) {
        final match = RegExp(r'COD Amount:\s*(\d+)').firstMatch(pkg.notes);
        if (match != null) {
          totalCodAmount += double.tryParse(match.group(1) ?? '') ?? 0.0;
        }
      }
    }

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
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Indicator & Title
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Session Summary',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(session.date),
                              style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2C2C2E), thickness: 1),
                
                // Content
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    children: [
                      const SizedBox(height: 16),
                      // Stats cards row
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryMiniCard(
                              'Rate', 
                              '${completionRate.toStringAsFixed(0)}%', 
                              const Color(0xFF30D158)
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryMiniCard(
                              'Stops (Del/Tot)', 
                              '$deliveredStops / $totalStops', 
                              const Color(0xFFF5A623)
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryMiniCard(
                              'COD Collected', 
                              '₹${totalCodAmount.toStringAsFixed(0)}', 
                              const Color(0xFF30D158)
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Detailed counts
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _buildStatDetailRow('Total Packages', '$totalPackages', Colors.white),
                            const Divider(color: Color(0xFF1C1C1E)),
                            _buildStatDetailRow('Delivered Packages', '$deliveredPackages', const Color(0xFF30D158)),
                            const Divider(color: Color(0xFF1C1C1E)),
                            _buildStatDetailRow('Failed Packages', '$failedPackages', const Color(0xFFFF453A)),
                            if (pendingPackages > 0) ...[
                              const Divider(color: Color(0xFF1C1C1E)),
                              _buildStatDetailRow('Unresolved Packages', '$pendingPackages', const Color(0xFF8E8E93)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      const Text(
                        'Delivery Stops',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      
                      // List of stops
                      if (stops.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24.0),
                            child: Text('No stops in this session.', style: TextStyle(color: Color(0xFF8E8E93))),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: stops.length,
                          itemBuilder: (context, index) {
                            final stop = stops[index];
                            final bool isStopDelivered = stop.isDelivered;
                            final bool isStopFailed = stop.isFailed;

                            Color statusColor = const Color(0xFF8E8E93);
                            String statusLabel = 'Pending';
                            IconData statusIcon = Icons.hourglass_empty;

                            if (isStopDelivered) {
                              statusColor = const Color(0xFF30D158);
                              statusLabel = 'Delivered';
                              statusIcon = Icons.check_circle;
                            } else if (isStopFailed) {
                              statusColor = const Color(0xFFFF453A);
                              statusLabel = 'Failed';
                              statusIcon = Icons.cancel;
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                stop.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildStopTypeBadge(stop),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(statusIcon, color: statusColor, size: 12),
                                            const SizedBox(width: 4),
                                            Text(
                                              statusLabel,
                                              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    stop.addressText,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                                  ),
                                  if (stop.combinedNotes.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Notes: ${stop.combinedNotes}',
                                      style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryMiniCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatDetailRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
