import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/receiver_record.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

class ReceiversBookScreen extends StatefulWidget {
  const ReceiversBookScreen({Key? key}) : super(key: key);

  @override
  State<ReceiversBookScreen> createState() => _ReceiversBookScreenState();
}

class _ReceiversBookScreenState extends State<ReceiversBookScreen> {
  List<ReceiverRecord> _allReceivers = [];
  List<ReceiverRecord> _filteredReceivers = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String _filterType = 'All'; // 'All' | 'Verified' | 'Unverified'

  void _openAddReceiverSheet() {
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
      builder: (context) => const _AddReceiverSheet(),
    ).then((value) {
      if (value == true) {
        _loadReceivers();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadReceivers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReceivers() async {
    setState(() => _isLoading = true);
    final list = await DatabaseHelper.instance.getAllReceivers();
    setState(() {
      _allReceivers = list;
      _filteredReceivers = list;
      _isLoading = false;
    });
    _applyFilterAndSearch();
  }

  void _onSearchChanged() {
    _applyFilterAndSearch();
  }

  void _applyFilterAndSearch() {
    final query = _searchController.text.toLowerCase().trim();
    List<ReceiverRecord> list = List.from(_allReceivers);

    // Filter by type
    if (_filterType == 'Verified') {
      list = list.where((r) => r.isVerified).toList();
    } else if (_filterType == 'Unverified') {
      list = list.where((r) => !r.isVerified).toList();
    }

    // Filter by search query
    if (query.isNotEmpty) {
      list = list.where((r) {
        return r.name.toLowerCase().contains(query) ||
            r.addressText.toLowerCase().contains(query);
      }).toList();
    }

    setState(() {
      _filteredReceivers = list;
    });
  }

  void _changeFilter(String type) {
    setState(() {
      _filterType = type;
    });
    _applyFilterAndSearch();
  }

  // Open Receiver Profile detail bottom sheet
  void _openReceiverProfile(ReceiverRecord receiver) {
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
      builder: (context) => _buildReceiverProfileSheet(receiver),
    );
  }

  Widget _buildReceiverProfileSheet(ReceiverRecord receiver) {
    final notesController = TextEditingController(text: receiver.notes);
    final Set<Marker> markers = {
      Marker(
        markerId: MarkerId(receiver.id),
        position: LatLng(receiver.latitude, receiver.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      )
    };

    return StatefulBuilder(
      builder: (context, setSheetState) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      receiver.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                receiver.addressText,
                style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
              ),
              const SizedBox(height: 16),
              // Mini Map
              const Text('📍 SAVED LOCATION', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(receiver.latitude, receiver.longitude),
                      zoom: 15,
                    ),
                    markers: markers,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Notes
              const Text('📝 AGENT NOTES', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  fillColor: const Color(0xFF2C2C2E),
                  filled: true,
                  hintText: 'Add notes for this receiver...',
                  hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              // Save & Delete buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5A623),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final updated = receiver.copyWith(notes: notesController.text);
                        await DatabaseHelper.instance.updateReceiver(updated);
                        Navigator.pop(context);
                        _loadReceivers();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Notes updated successfully.')),
                        );
                      },
                      child: const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFFF453A)),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1C1C1E),
                          title: const Text('Delete Receiver?', style: TextStyle(color: Colors.white)),
                          content: const Text(
                            'This will delete this receiver and their saved location from your address book.',
                            style: TextStyle(color: Color(0xFF8E8E93)),
                          ),
                          actions: [
                            TextButton(
                              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
                              onPressed: () => Navigator.pop(context, false),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
                              child: const Text('Delete'),
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await DatabaseHelper.instance.deleteReceiver(receiver.id);
                        Navigator.pop(context); // close sheet
                        _loadReceivers();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Receivers Directory',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFFF5A623), size: 28),
                  onPressed: _openAddReceiverSheet,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Search Input
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                fillColor: const Color(0xFF1C1C1E),
                filled: true,
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
                hintText: 'Search by name or address...',
                hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            // Filter Pills
            Row(
              children: [
                _buildFilterPill('All'),
                const SizedBox(width: 8),
                _buildFilterPill('Verified'),
                const SizedBox(width: 8),
                _buildFilterPill('Unverified'),
              ],
            ),
            const SizedBox(height: 16),
            // Receivers List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5A623)))
                  : _filteredReceivers.isEmpty
                      ? const Center(
                          child: Text('No receivers found.', style: TextStyle(color: Color(0xFF8E8E93))),
                        )
                      : ListView.builder(
                          itemCount: _filteredReceivers.length,
                          itemBuilder: (context, index) {
                            final receiver = _filteredReceivers[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF2C2C2E),
                                  child: Icon(
                                    Icons.person_outline,
                                    color: receiver.isVerified ? const Color(0xFF30D158) : const Color(0xFF8E8E93),
                                  ),
                                ),
                                title: Text(
                                  receiver.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                subtitle: Text(
                                  receiver.addressText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                                ),
                                trailing: Icon(
                                  receiver.isVerified ? Icons.verified_user_outlined : Icons.help_outline,
                                  size: 18,
                                  color: receiver.isVerified ? const Color(0xFF30D158) : const Color(0xFFFF9F0A),
                                ),
                                onTap: () => _openReceiverProfile(receiver),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildFilterPill(String type) {
    final isSelected = _filterType == type;
    return GestureDetector(
      onTap: () => _changeFilter(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF5A623) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.transparent : const Color(0xFF2C2C2E),
          ),
        ),
        child: Text(
          type,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AddReceiverSheet extends StatefulWidget {
  const _AddReceiverSheet({Key? key}) : super(key: key);

  @override
  State<_AddReceiverSheet> createState() => _AddReceiverSheetState();
}

class _AddReceiverSheetState extends State<_AddReceiverSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLocating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _latController.text = pos.latitude.toString();
      _lngController.text = pos.longitude.toString();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get GPS location: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _saveReceiver() async {
    if (!_formKey.currentState!.validate()) return;

    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid latitude and longitude numbers')),
      );
      return;
    }

    final newReceiver = ReceiverRecord(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      addressText: _addressController.text.trim(),
      latitude: lat,
      longitude: lng,
      notes: _notesController.text.trim(),
      deliveryCount: 0,
      lastDelivered: null,
      isVerified: true,
    );

    await DatabaseHelper.instance.insertReceiver(newReceiver);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add New Receiver',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('NAME', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  fillColor: const Color(0xFF2C2C2E),
                  filled: true,
                  hintText: 'Enter buyer name',
                  hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              const Text('ADDRESS', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  fillColor: const Color(0xFF2C2C2E),
                  filled: true,
                  hintText: 'Enter address detail',
                  hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Address is required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('COORDINATES', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    icon: _isLocating 
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF5A623)))
                      : const Icon(Icons.my_location, size: 14, color: Color(0xFFF5A623)),
                    label: const Text('GET CURRENT GPS', style: TextStyle(color: Color(0xFFF5A623), fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _isLocating ? null : _getCurrentLocation,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        fillColor: const Color(0xFF2C2C2E),
                        filled: true,
                        hintText: 'Latitude',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Lat is required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        fillColor: const Color(0xFF2C2C2E),
                        filled: true,
                        hintText: 'Longitude',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Lng is required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('📝 NOTES', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  fillColor: const Color(0xFF2C2C2E),
                  filled: true,
                  hintText: 'Enter notes (e.g., house color, landmarks)',
                  hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
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
                  onPressed: _saveReceiver,
                  child: const Text(
                    'ADD RECEIVER',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
