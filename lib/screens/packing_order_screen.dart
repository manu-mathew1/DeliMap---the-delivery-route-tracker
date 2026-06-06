import 'package:flutter/material.dart';
import '../models/package_item.dart';

class PackingOrderScreen extends StatefulWidget {
  final List<PackageItem> packages;

  const PackingOrderScreen({
    Key? key,
    required this.packages,
  }) : super(key: key);

  @override
  State<PackingOrderScreen> createState() => _PackingOrderScreenState();
}

class _PackingOrderScreenState extends State<PackingOrderScreen> {
  List<PackageItem> _packingList = [];
  final Set<String> _packedItems = {};

  @override
  void initState() {
    super.initState();
    // Reverse the package delivery order for packing:
    // The last package to be delivered is packed first (goes to bottom of bag)
    // The first package to be delivered is packed last (goes to top of bag)
    _packingList = List.from(widget.packages.reversed);
  }

  void _togglePacked(String id) {
    setState(() {
      if (_packedItems.contains(id)) {
        _packedItems.remove(id);
      } else {
        _packedItems.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _packingList.length - _packedItems.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('🎒 Bag Packing Guide', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Pack your bag in this order:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              const Text(
                'Start packing from the top of this list (goes to the bottom of your bag). Your first delivery will end up at the very top.',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
              const SizedBox(height: 16),
              // Header indicator
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF453A).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF453A), width: 1),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_downward, color: Color(0xFFFF453A), size: 16),
                    SizedBox(width: 8),
                    Text(
                      '⬇️ PACK THESE FIRST (Bottom of Bag)',
                      style: TextStyle(color: Color(0xFFFF453A), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // List of packages to pack
              Expanded(
                child: ListView.builder(
                  itemCount: _packingList.length,
                  itemBuilder: (context, index) {
                    final pkg = _packingList[index];
                    final isPacked = _packedItems.contains(pkg.id);
                    final isLastToPack = index == _packingList.length - 1;

                    // The original delivery stop number (1-indexed)
                    final stopNumber = widget.packages.indexOf(pkg) + 1;

                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isPacked ? const Color(0xFF1C1C1E).withOpacity(0.4) : const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(12),
                            border: isPacked
                                ? Border.all(color: const Color(0xFF2C2C2E), width: 1)
                                : Border.all(color: Colors.transparent, width: 1),
                          ),
                          child: ListTile(
                            leading: Checkbox(
                              value: isPacked,
                              activeColor: const Color(0xFF30D158),
                              onChanged: (_) => _togglePacked(pkg.id),
                            ),
                            title: Text(
                              pkg.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPacked ? const Color(0xFF8E8E93) : Colors.white,
                                decoration: isPacked ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: Text(
                              'Stop $stopNumber · ${pkg.addressText}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF8E8E93),
                                decoration: isPacked ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPacked ? Colors.transparent : const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Pack #${index + 1}',
                                style: TextStyle(
                                  color: isPacked ? const Color(0xFF8E8E93) : const Color(0xFFF5A623),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (isLastToPack) ...[
                          const SizedBox(height: 8),
                          // Footer indicator
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF30D158).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF30D158), width: 1),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.arrow_upward, color: Color(0xFF30D158), size: 16),
                                SizedBox(width: 8),
                                Text(
                                  '🔝 PACK THESE LAST (Top of Bag - Deliver First)',
                                  style: TextStyle(color: Color(0xFF30D158), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Start Delivery Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  onPressed: () {
                    // Check if everything is packed, warn if not
                    if (pendingCount > 0) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1C1C1E),
                          title: const Text('Unpacked Packages', style: TextStyle(color: Colors.white)),
                          content: Text(
                            'You still have $pendingCount package(s) unmarked as packed. Start delivery anyway?',
                            style: const TextStyle(color: Color(0xFF8E8E93)),
                          ),
                          actions: [
                            TextButton(
                              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
                              onPressed: () => Navigator.pop(context),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5A623)),
                              child: const Text('Yes, Start', style: TextStyle(color: Colors.black)),
                              onPressed: () {
                                Navigator.pop(context); // pop dialog
                                Navigator.pop(context); // pop screen
                              },
                            ),
                          ],
                        ),
                      );
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text(
                    '🚀  START DELIVERY',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
