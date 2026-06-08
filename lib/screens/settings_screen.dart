import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';

enum CloudConnectionStatus {
  disabled,
  checking,
  offline,
  connected,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _appLockEnabled = true;
  bool _googleSyncEnabled = false;
  String? _googleEmail;
  bool _isSyncing = false;
  String _startLocationType = 'Current GPS';
  CloudConnectionStatus _connectionStatus = CloudConnectionStatus.disabled;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _appLockEnabled = prefs.getBool('app_lock_enabled') ?? true;
        _googleSyncEnabled = prefs.getBool('google_sync_enabled') ?? false;
        _googleEmail = prefs.getString('google_email');
        _startLocationType = prefs.getString('start_location_type') ?? 'Current GPS';
      });
      await _checkConnection();
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _checkConnection() async {
    if (!_googleSyncEnabled || _googleEmail == null) {
      if (mounted) {
        setState(() {
          _connectionStatus = CloudConnectionStatus.disabled;
          _connectionError = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _connectionStatus = CloudConnectionStatus.checking;
        _connectionError = null;
      });
    }

    try {
      await CloudSyncService.checkConnection();
      if (mounted) {
        setState(() {
          _connectionStatus = CloudConnectionStatus.connected;
          _connectionError = null;
        });
      }
    } catch (e) {
      print('CloudSyncService: Connection check failed: $e');
      if (mounted) {
        setState(() {
          _connectionStatus = CloudConnectionStatus.offline;
          _connectionError = e.toString();
        });
      }
    }
  }

  Color _getStatusColor() {
    switch (_connectionStatus) {
      case CloudConnectionStatus.disabled:
        return const Color(0xFF8E8E93);
      case CloudConnectionStatus.checking:
        return const Color(0xFFF5A623);
      case CloudConnectionStatus.offline:
        return const Color(0xFFFF453A);
      case CloudConnectionStatus.connected:
        return const Color(0xFF30D158);
    }
  }

  String _getStatusText() {
    switch (_connectionStatus) {
      case CloudConnectionStatus.disabled:
        return 'Sync Disabled';
      case CloudConnectionStatus.checking:
        return 'Checking connection...';
      case CloudConnectionStatus.offline:
        return 'Offline (Using Local Cache)';
      case CloudConnectionStatus.connected:
        return 'Connected to Cloud Database';
    }
  }

  Future<void> _toggleAppLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', value);
    setState(() {
      _appLockEnabled = value;
    });
  }

  Future<void> _toggleGoogleSync(bool value) async {
    if (value) {
      // Prompt Google Sign-In
      await _handleGoogleSignIn();
    } else {
      // Simply disable sync locally, keep Google account but don't sync
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_sync_enabled', false);
      setState(() {
        _googleSyncEnabled = false;
      });
      await _checkConnection();
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isSyncing = true;
    });
    try {
      final user = await AuthService.signInWithGoogle();
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('google_sync_enabled', true);
        await prefs.setString('google_uid', user.uid);
        await prefs.setString('google_email', user.email ?? '');
        await prefs.setString('google_display_name', user.displayName ?? '');
        
        setState(() {
          _googleSyncEnabled = true;
          _googleEmail = user.email;
        });

        // Trigger immediate bidirectional sync
        await CloudSyncService.syncReceivers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Linked Google Account: ${user.email}'),
              backgroundColor: const Color(0xFF30D158),
            ),
          );
        }
      } else {
        setState(() {
          _googleSyncEnabled = false;
        });
      }
    } catch (e) {
      setState(() {
        _googleSyncEnabled = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In failed: $e'),
            backgroundColor: const Color(0xFFFF453A),
          ),
        );
      }
    } finally {
      await _checkConnection();
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    setState(() {
      _isSyncing = true;
    });
    try {
      await AuthService.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_sync_enabled', false);
      await prefs.remove('google_uid');
      await prefs.remove('google_email');
      await prefs.remove('google_display_name');

      setState(() {
        _googleSyncEnabled = false;
        _googleEmail = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out from Google Account.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
    } finally {
      await _checkConnection();
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _syncCloudNow() async {
    if (_googleEmail == null) {
      await _handleGoogleSignIn();
      return;
    }

    setState(() {
      _isSyncing = true;
    });
    try {
      await CloudSyncService.syncReceivers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cloud Database sync complete!'),
            backgroundColor: Color(0xFF30D158),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: const Color(0xFFFF453A),
          ),
        );
      }
    } finally {
      await _checkConnection();
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  void _clearData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Clear Database?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete all session history, scanned packages, and saved receiver coordinates. This cannot be undone.',
          style: TextStyle(color: Color(0xFF8E8E93)),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
            child: const Text('Clear Everything'),
            onPressed: () async {
              // Re-create tables
              final db = await DatabaseHelper.instance.database;
              await db.execute('DROP TABLE IF EXISTS packages');
              await db.execute('DROP TABLE IF EXISTS sessions');
              await db.execute('DROP TABLE IF EXISTS receivers');
              
              // Re-run setup
              await db.execute('''
                CREATE TABLE receivers (
                  id TEXT PRIMARY KEY,
                  name TEXT NOT NULL,
                  address_text TEXT NOT NULL,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL,
                  notes TEXT NOT NULL,
                  delivery_count INTEGER NOT NULL,
                  last_delivered TEXT,
                  is_verified INTEGER NOT NULL,
                  last_updated INTEGER DEFAULT 0
                )
              ''');
              await db.execute('CREATE INDEX idx_receivers_name_address ON receivers (name, address_text)');
              await db.execute('''
                CREATE TABLE sessions (
                  id TEXT PRIMARY KEY,
                  date TEXT NOT NULL,
                  status TEXT NOT NULL
                )
              ''');
              await db.execute('''
                CREATE TABLE packages (
                  id TEXT PRIMARY KEY,
                  session_id TEXT NOT NULL,
                  name TEXT NOT NULL,
                  address_text TEXT NOT NULL,
                  status TEXT NOT NULL,
                  scanned_at TEXT NOT NULL,
                  delivered_at TEXT,
                  receiver_id TEXT,
                  latitude REAL,
                  longitude REAL,
                  notes TEXT NOT NULL,
                  FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
                )
              ''');

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Database cleared successfully.')),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _exportCSV() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final receivers = await DatabaseHelper.instance.getAllReceivers();
      if (receivers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No receivers found to export.')),
          );
        }
        return;
      }

      final csvBuffer = StringBuffer();
      csvBuffer.writeln('ID,Name,Address,Latitude,Longitude,Notes,DeliveryCount,LastDelivered,IsVerified,LastUpdated');

      for (final r in receivers) {
        csvBuffer.writeln(
          '"${r.id}",'
          '"${r.name.replaceAll('"', '""')}",'
          '"${r.addressText.replaceAll('"', '""')}",'
          '${r.latitude},'
          '${r.longitude},'
          '"${r.notes.replaceAll('"', '""')}",'
          '${r.deliveryCount},'
          '"${r.lastDelivered?.toIso8601String() ?? ''}",'
          '${r.isVerified ? 1 : 0},'
          '${r.lastUpdated}'
        );
      }

      String filePath = '';
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          filePath = '${downloadDir.path}/delimap_receivers.csv';
          final file = File(filePath);
          await file.writeAsString(csvBuffer.toString());
        } else {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            filePath = '${externalDir.path}/delimap_receivers.csv';
            final file = File(filePath);
            await file.writeAsString(csvBuffer.toString());
          }
        }
      } else {
        final appDocDir = await getApplicationDocumentsDirectory();
        filePath = '${appDocDir.path}/delimap_receivers.csv';
        final file = File(filePath);
        await file.writeAsString(csvBuffer.toString());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV downloaded to: $filePath'),
            backgroundColor: const Color(0xFF30D158),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV download failed: $e'),
            backgroundColor: const Color(0xFFFF453A),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _updateStartLocation(String val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('start_location_type', val);
    setState(() {
      _startLocationType = val;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: ListView(
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (_isSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5A623)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Routing Preferences
            const Text('🗺️  ROUTING', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: const Text('Starting Point', style: TextStyle(color: Colors.white)),
                subtitle: Text(_startLocationType, style: const TextStyle(color: Color(0xFF8E8E93))),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF8E8E93)),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1C1C1E),
                      title: const Text('Select Route Start Location', style: TextStyle(color: Colors.white)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('Current GPS position', style: TextStyle(color: Colors.white)),
                            leading: Radio<String>(
                              value: 'Current GPS',
                              groupValue: _startLocationType,
                              onChanged: (val) {
                                if (val != null) {
                                  _updateStartLocation(val);
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ),
                          ListTile(
                            title: const Text('Warehouse / Custom Base', style: TextStyle(color: Colors.white)),
                            leading: Radio<String>(
                              value: 'Warehouse',
                              groupValue: _startLocationType,
                              onChanged: (val) {
                                if (val != null) {
                                  _updateStartLocation(val);
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Cloud Sync settings
            const Text('☁️  CLOUD BACKUP', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Cloud Database Sync', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Auto-sync receivers directory to cloud', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                    value: _googleSyncEnabled,
                    activeColor: const Color(0xFFF5A623),
                    onChanged: _toggleGoogleSync,
                  ),
                  const Divider(color: Color(0xFF2C2C2E), height: 1),
                  ListTile(
                    title: const Text('Database Connection', style: TextStyle(color: Colors.white, fontSize: 15)),
                    leading: const Icon(Icons.cloud_queue_rounded, color: Color(0xFF8E8E93)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getStatusColor(),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getStatusText(),
                              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                            ),
                          ],
                        ),
                        if (_connectionError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _connectionError!,
                            style: const TextStyle(color: Color(0xFFFF453A), fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    onTap: _connectionError != null
                        ? () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF1C1C1E),
                                title: const Text('Connection Error Details', style: TextStyle(color: Colors.white)),
                                content: SingleChildScrollView(
                                  child: Text(
                                    _connectionError!,
                                    style: const TextStyle(color: Color(0xFFFF453A)),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: const Text('Close', style: TextStyle(color: Color(0xFF8E8E93))),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  TextButton(
                                    child: const Text('Retry', style: TextStyle(color: Color(0xFFF5A623))),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _checkConnection();
                                    },
                                  ),
                                ],
                              ),
                            );
                          }
                        : null,
                    trailing: _connectionStatus == CloudConnectionStatus.checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5A623)),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF8E8E93)),
                            onPressed: _checkConnection,
                          ),
                  ),
                  const Divider(color: Color(0xFF2C2C2E), height: 1),
                  if (_googleEmail != null) ...[
                    ListTile(
                      title: const Text('Google Account', style: TextStyle(color: Colors.white)),
                      subtitle: Text(_googleEmail!, style: const TextStyle(color: Color(0xFF30D158), fontSize: 13, fontWeight: FontWeight.w500)),
                      trailing: TextButton(
                        onPressed: _handleSignOut,
                        child: const Text('Disconnect', style: TextStyle(color: Color(0xFFFF453A))),
                      ),
                    ),
                    const Divider(color: Color(0xFF2C2C2E), height: 1),
                    ListTile(
                      title: const Text('Sync Databases Now', style: TextStyle(color: Colors.white)),
                      leading: const Icon(Icons.sync_rounded, color: Color(0xFFF5A623)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF8E8E93)),
                      onTap: _syncCloudNow,
                    ),
                  ] else ...[
                    ListTile(
                      title: const Text('Connect Google Account', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Sign in to backup your receivers directory', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                      leading: const Icon(Icons.login_rounded, color: Color(0xFFF5A623)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF8E8E93)),
                      onTap: _handleGoogleSignIn,
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Security settings
            const Text('🔒  SECURITY', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: const Text('App Lock', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Biometric / PIN on start', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                value: _appLockEnabled,
                activeColor: const Color(0xFFF5A623),
                onChanged: _toggleAppLock,
              ),
            ),
            const SizedBox(height: 24),

            // Data settings
            const Text('📊  DATA MANAGEMENT', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Export Receivers to CSV', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Saves to public Download folder', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                    leading: const Icon(Icons.file_download_outlined, color: Color(0xFFF5A623)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF8E8E93)),
                    onTap: _exportCSV,
                  ),
                  const Divider(color: Color(0xFF2C2C2E), height: 1),
                  ListTile(
                    title: const Text('Clear All Session History', style: TextStyle(color: Color(0xFFFF453A))),
                    subtitle: const Text('Deletes all sessions, packages & routes', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                    leading: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFFF453A)),
                    onTap: _clearData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Version Info
            const Center(
              child: Column(
                children: [
                  Text(
                    'DeliMap v1.8.3',
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Built specifically for delivery agents.',
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
