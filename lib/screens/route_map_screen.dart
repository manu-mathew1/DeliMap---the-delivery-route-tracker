import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/delivery_session.dart';
import '../models/package_item.dart';
import '../models/receiver_record.dart';
import '../models/delivery_stop.dart';
import '../services/route_service.dart';
import '../services/directions_service.dart';
import 'dart:async';

class RouteMapScreen extends StatefulWidget {
  final DeliverySession? activeSession;
  final VoidCallback onDataChanged;

  const RouteMapScreen({
    Key? key,
    required this.activeSession,
    required this.onDataChanged,
  }) : super(key: key);

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  List<DeliveryStop> _orderedStops = [];
  bool _isLoading = true;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Map markers & polylines
  final Map<MarkerId, Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _loadRouteData();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _startLocationTracking() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });
          _updateRouteWithNewStartPoint(position.latitude, position.longitude);
        }
      },
      onError: (error) {
        print('Live location stream error: $error');
      },
    );
  }

  Future<void> _updateRouteWithNewStartPoint(double startLat, double startLng) async {
    await _buildMarkersAndPolylines(startLat, startLng);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadRouteData() async {
    setState(() => _isLoading = true);
    
    // 1. Get current GPS location (default fallback)
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _startLocationTracking();
      }
    } catch (e) {
      print('GPS fetching error: $e');
    }

    // Default coordinates (e.g. Kanjirapally coordinates if GPS unavailable)
    double startLat = _currentPosition?.latitude ?? 9.5564;
    double startLng = _currentPosition?.longitude ?? 76.7871;

    // 2. Fetch packages in active session
    if (widget.activeSession != null) {
      final pkgs = await DatabaseHelper.instance.getPackagesInSession(widget.activeSession!.id);
      
      final stops = RouteService.groupPackagesIntoStops(pkgs);

      // Calculate optimized route
      _orderedStops = RouteService.optimizeRoute(
        startLatitude: startLat,
        startLongitude: startLng,
        stops: stops,
      );

      await _buildMarkersAndPolylines(startLat, startLng);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _buildMarkersAndPolylines(double startLat, double startLng) async {
    _markers.clear();
    _polylines.clear();

    // Add starting point marker (Home / Hub)
    final startId = const MarkerId('start_point');
    final startMarker = Marker(
      markerId: startId,
      position: LatLng(startLat, startLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: const InfoWindow(title: 'Starting Point'),
    );
    _markers[startId] = startMarker;

    // Filter pending and completed stops that have valid coordinates
    final pendingStops = _orderedStops
        .where((s) => s.isPending && s.latitude != null && s.longitude != null)
        .toList();
    final deliveredStops = _orderedStops
        .where((s) => (s.isDelivered || s.isFailed) && s.latitude != null && s.longitude != null)
        .toList();

    // Add stop markers
    for (int i = 0; i < _orderedStops.length; i++) {
      final stop = _orderedStops[i];
      if (stop.latitude == null || stop.longitude == null) continue;

      final markerId = MarkerId(stop.id);
      final isCurrent = pendingStops.isNotEmpty && stop.id == pendingStops.first.id;
      final isDelivered = stop.isDelivered;

      double hue = BitmapDescriptor.hueRed; // default
      if (isDelivered) {
        hue = BitmapDescriptor.hueGreen; // completed
      } else if (isCurrent) {
        hue = BitmapDescriptor.hueOrange; // current/amber
      } else if (stop.packages.any((p) => p.receiverId == null)) {
        hue = BitmapDescriptor.hueYellow; // has any unverified/new package
      }

      final pkgCountText = stop.packages.length > 1 ? ' (${stop.packages.length} pkg)' : '';

      final marker = Marker(
        markerId: markerId,
        position: LatLng(stop.latitude!, stop.longitude!),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: 'Stop ${i + 1}: ${stop.name}$pkgCountText',
          snippet: stop.addressText,
        ),
        draggable: stop.packages.any((p) => p.receiverId == null), // Allow dragging to refine coordinates if new
        onDragEnd: (newPosition) {
          _updateStopCoordinates(stop, newPosition.latitude, newPosition.longitude);
        },
      );

      _markers[markerId] = marker;
    }

    final List<LatLng> pendingCoords = pendingStops.map((s) => LatLng(s.latitude!, s.longitude!)).toList();

    List<LatLng>? routePoints;
    if (pendingCoords.isNotEmpty) {
      routePoints = await DirectionsService.fetchRoutePoints(
        startLat: startLat,
        startLng: startLng,
        stops: pendingCoords,
      );
    }

    // Fallback: draw straight-line connection if Directions API fails or offline
    if (routePoints == null) {
      print('Directions Service fallback: drawing straight-line connections.');
      routePoints = [LatLng(startLat, startLng)];
      routePoints.addAll(pendingCoords);
      routePoints.addAll(deliveredStops.map((s) => LatLng(s.latitude!, s.longitude!)));
    }

    // Create polyline route guide
    if (routePoints.length > 1) {
      final routePolyline = Polyline(
        polylineId: const PolylineId('route_guide'),
        points: routePoints,
        color: const Color(0xFFF5A623),
        width: 5,
        geodesic: true,
      );
      _polylines.add(routePolyline);
    }
  }

  // Refine coordinates (drag-and-drop verification at the hub)
  Future<void> _updateStopCoordinates(DeliveryStop stop, double lat, double lng) async {
    for (final pkg in stop.packages) {
      final updated = pkg.copyWith(latitude: lat, longitude: lng);
      await DatabaseHelper.instance.updatePackage(updated);
    }
    _loadRouteData();
    widget.onDataChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pin location updated for ${stop.name}')),
    );
  }

  // Launch Google / Apple Maps for turn-by-turn navigation
  Future<void> _launchNavigation(DeliveryStop stop) async {
    if (stop.latitude == null || stop.longitude == null) return;
    
    final googleMapsUrl = Uri.parse('google.navigation:q=${stop.latitude},${stop.longitude}&mode=d');
    final appleMapsUrl = Uri.parse('http://maps.apple.com/?daddr=${stop.latitude},${stop.longitude}');

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl);
    } else if (await canLaunchUrl(appleMapsUrl)) {
      await launchUrl(appleMapsUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch turn-by-turn navigation.')),
      );
    }
  }

  // Mark all pending packages at stop delivered and open post-delivery popup
  Future<void> _markDelivered(DeliveryStop stop) async {
    final bool? shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => _buildPostDeliveryDialog(stop),
    );

    if (shouldSave == true) {
      _loadRouteData();
      widget.onDataChanged();
    }
  }

  Widget _buildPostDeliveryDialog(DeliveryStop stop) {
    bool locationCorrect = true;
    final notesController = TextEditingController(text: stop.combinedNotes);

    return StatefulBuilder(
      builder: (context, setDialogState) {
        final pendingCount = stop.packages.where((p) => p.status == PackageStatus.pending).length;
        final countText = pendingCount > 1 ? ' ($pendingCount packages)' : '';

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
                // Determine coordinates to save
                double lat = stop.latitude!;
                double lng = stop.longitude!;

                if (!locationCorrect) {
                  // If location is wrong, we fetch current GPS coords
                  try {
                    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
                    lat = pos.latitude;
                    lng = pos.longitude;
                  } catch (e) {
                    print('Failed to get current position for correction: $e');
                  }
                }

                // Find or generate receiver record ID
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

                // Create or update receiver record in database
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

                // Update all pending packages at this stop to delivered
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeSession == null) {
      return const Center(
        child: Text('No active delivery session.', style: TextStyle(color: Color(0xFF8E8E93))),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFF5A623)));
    }

    final pendingStops = _orderedStops.where((s) => s.isPending).toList();

    if (pendingStops.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Color(0xFF30D158)),
            SizedBox(height: 16),
            Text('All deliveries completed!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    final currentStop = pendingStops.first;
    final startLat = _currentPosition?.latitude ?? 9.5564;
    final startLng = _currentPosition?.longitude ?? 76.7871;

    final isKnown = currentStop.packages.any((p) => p.receiverId != null);
    final stopIndex = _orderedStops.indexOf(currentStop);
    final pkgCountText = currentStop.packages.length > 1 ? ' (${currentStop.packages.length} packages)' : '';

    return Stack(
      children: [
        // 1. Google Map
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(currentStop.latitude ?? startLat, currentStop.longitude ?? startLng),
            zoom: 14.0,
          ),
          onMapCreated: (controller) => _mapController = controller,
          markers: _markers.values.toSet(),
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: false,
          mapType: MapType.normal,
        ),
        // 2. Current Stop Detail Card (Bottom HUD)
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'NEXT STOP (Stop ${stopIndex + 1})',
                      style: const TextStyle(color: Color(0xFFF5A623), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (isKnown)
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF30D158), size: 14),
                          SizedBox(width: 4),
                          Text('Known Location', style: TextStyle(color: Color(0xFF30D158), fontSize: 11)),
                        ],
                      )
                    else
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9F0A), size: 14),
                          SizedBox(width: 4),
                          Text('New Address', style: TextStyle(color: Color(0xFFFF9F0A), fontSize: 11)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${currentStop.name}$pkgCountText',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  currentStop.addressText,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                ),
                if (currentStop.combinedNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.note_alt_outlined, color: Color(0xFFF5A623), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentStop.combinedNotes,
                            style: const TextStyle(fontSize: 12, color: Colors.white, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.navigation_outlined, color: Colors.black),
                          label: const Text('🧭 NAVIGATE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF5A623),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          onPressed: () => _launchNavigation(currentStop),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: const Text('DELIVERED', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF30D158),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          onPressed: () => _markDelivered(currentStop),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
