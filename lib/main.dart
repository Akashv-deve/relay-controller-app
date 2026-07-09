import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // 👇 NEEDED FOR HAPTIC VIBRATION
import 'dart:convert'; // To parse the JSON data
// 👇 ADD THIS: Required for opening the raw UDP network socket
import 'dart:io';
import 'package:http/http.dart' as http; // To make the API calls
import 'dart:ui'; // 👇 NEEDED FOR FROSTED GLASS EFFECTS
import 'dart:math'; // 👇 NEW: NEEDED FOR RANDOM NUMBER GENERATION
import 'models/smart_scene.dart';

void main() async { 
  WidgetsFlutterBinding.ensureInitialized(); 
  
  // 👇 NEW: Check memory before booting the UI
  final prefs = await SharedPreferences.getInstance();
  final savedIp = prefs.getString('active_hub_ip');

  runApp(SmartRelayApp(initialIp: savedIp));
}

class SmartRelayApp extends StatefulWidget {
  final String? initialIp; // 👇 NEW: Receives the IP from main()

  const SmartRelayApp({super.key, this.initialIp});

  static SmartRelayAppState of(BuildContext context) =>
      context.findAncestorStateOfType<SmartRelayAppState>()!;

  @override
  State<SmartRelayApp> createState() => SmartRelayAppState();
}

class SmartRelayAppState extends State<SmartRelayApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relay Controller',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode, 
      
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        scaffoldBackgroundColor: Colors.grey[100],
        cardColor: Colors.white,
      ),
      
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF121212), 
        cardColor: const Color(0xFF1E1E1E), 
      ),
     
      // 👇 NEW ROUTING LOGIC: If no IP is saved, open the Scanner. Otherwise, open the Control Panel!
      home: widget.initialIp == null 
          ? const HubDiscoveryScreen() 
          : ControlPanelScreen(hubIp: widget.initialIp!), 
    );
  }
}


class SmartDevice {
  final String id;
  final String name;
  final String description;
  String iconUrl;
  String state;
  String physicalState;

  final bool hasPwm;
  double pwmValue;
  final String pwmLabel;

  final String room;
  bool isOnline;
  bool isLockedByOther;
  final bool isUsedInLogic; // true only when this output is used in Configure logic

final bool isUsedInScene;

// none, logic, scene, force
String ownerType;
String ownerName;

bool get isSceneOwned => ownerType == 'scene';

bool get isProtectedOutput =>
    isUsedInLogic || isUsedInScene || isSceneOwned;

bool get isFreeOutput =>
    !isUsedInLogic && !isUsedInScene && !isSceneOwned;

 final String kind; // 'relay', 'pwm', or 'analog'
final String port; // example: PWM1 or ANA1

bool get isPwmOutput => kind == 'pwm';
bool get isAnalogOutput => kind == 'analog';
bool get isRelayOutput => kind == 'relay';

  SmartDevice({
    required this.id,
    required this.name,
    required this.description,
    required this.iconUrl,
    this.state = 'AUTO',
    this.physicalState = 'OFF',
    this.hasPwm = false,
    this.pwmValue = 50.0,
    this.pwmLabel = 'Intensity',
    this.room = 'Main Zone',
    this.isOnline = true,
    this.isLockedByOther = false,
    this.isUsedInLogic = false,
    this.isUsedInScene = false,
    this.ownerType = 'none',
    this.ownerName = '',
    this.kind = 'relay',
    this.port = '',
  });

  factory SmartDevice.fromJson(Map<String, dynamic> json) {
    return SmartDevice(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      iconUrl: json['iconUrl'] ?? '', 
      state: json['state'] ?? 'OFF',
      hasPwm: json['hasPwm'] ?? false,
      pwmValue: json['pwmValue']?.toDouble() ?? 50.0,
      pwmLabel: json['pwmLabel'] ?? 'Intensity',
      room: json['room'] ?? 'Main Zone',
      isOnline: json['isOnline'] ?? true, 
      // PIN/lock UI is disabled, but keep this field for old status payload compatibility
      isLockedByOther: json['isLockedByOther'] ?? false,
      isUsedInLogic: json['isUsedInLogic'] ?? false, 
      isUsedInScene: json['isUsedInScene'] ?? false,
ownerType: json['ownerType'] ?? 'none',
ownerName: json['ownerName'] ?? '',
    );
  }
}
// 👇 UPDATE THIS CLASS: Make it accept the IP as a parameter
class ControlPanelScreen extends StatefulWidget {
  final String hubIp;
  const ControlPanelScreen({super.key, required this.hubIp});

  @override
  State<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends State<ControlPanelScreen> with SingleTickerProviderStateMixin {
  
  late AnimationController _sceneGlowController;
  
  // 👇 DELETE `final String _baseUrl = 'http://192.168.1.27';` 
  // 👇 REPLACE IT WITH THIS: It reads the dynamic IP passed into the widget!
  late String _baseUrl;
// 👇 NEW: MOBILE UNIQUE CLIENT ID VARIABLES
  String _clientId = '';
  String _sessionId = '';
  String _clientName = '';

  final Map<String, String> _headers = {'Content-Type': 'application/json'};
  String? _activeScene;
  String? _hoveredScene;
  List<SmartDevice> _devices = [];
  List<SmartScene> _scenes = [];
  Timer? _syncTimer;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _baseUrl = widget.hubIp;
    _sceneGlowController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1200), 
    )..repeat(reverse: true);
    
    _bootControlPanel(); // 👇 NEW: Replaced the old 3 startup functions!
  }


String _safeEmojiForMobile(String emoji, {String fallback = '⚙️'}) {
  final e = emoji.trim();

  if (e.isEmpty) return fallback;

  // Some Android phones show these as box/cross.
  // Replace with safer common emojis.
  switch (e) {
    case '🔌':
      return '⚡'; // Power fallback
    case '🖲️':
      return '🎛️';
    default:
      return e;
  }
}


  // 👇 NEW: ALL OF HIS IDENTITY GENERATOR FUNCTIONS
  String _randomHex(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  String _generateClientId() {
    final time = DateTime.now().millisecondsSinceEpoch;
    return 'phone_${time}_${_randomHex(32)}'; 
  }

  String _generateSessionId() {
    final time = DateTime.now().millisecondsSinceEpoch;
    return 'session_${time}_${_randomHex(16)}';
  }

  Future<void> _loadClientIdentity() async {
    _prefs = await SharedPreferences.getInstance();

    String? savedId = _prefs.getString('client_id');
    if (savedId == null || savedId.isEmpty) {
      savedId = _generateClientId();
      await _prefs.setString('client_id', savedId);
    }

    _clientId = savedId;
    _sessionId = _generateSessionId();

    _clientName = _prefs.getString('client_name') ?? 'Mobile ${_clientId.substring(_clientId.length - 4)}';

    debugPrint('📱 Client ID: $_clientId');
    debugPrint('📱 Session ID: $_sessionId');
    debugPrint('📱 Client Name: $_clientName');
  }

  Future<void> _bootControlPanel() async {
    await _loadClientIdentity();
    _startLiveBackgroundSync();
    await _fetchDevicesFromServer();
  }

  // ✅ Finds which outputs are actually used in Configure logic.
  // Only these outputs need AUTO mode. Outputs not used in logic are simple ON/OFF or manual-only.
  Set<String> _logicOutputNamesFromConfigure(Map<String, dynamic> configure) {
    final Set<String> used = <String>{};

    final builders = configure['builders'];
    if (builders is List) {
      for (final builder in builders) {
        if (builder is Map) {
          final outputNodes = builder['outputNodes'];
          if (outputNodes is List) {
            for (final node in outputNodes) {
              _collectLogicOutputName(node, used);
            }
          }
        }
      }
    }

    return used;
  }

  void _collectLogicOutputName(dynamic node, Set<String> used) {
    if (node is String) {
      if (node.trim().isNotEmpty) used.add(node.trim());
      return;
    }

    if (node is Map) {
      final String name = (node['name'] ?? node['output'] ?? node['target'] ?? '').toString().trim();
      if (name.isNotEmpty) used.add(name);

      final children = node['children'];
      if (children is List) {
        for (final child in children) {
          _collectLogicOutputName(child, used);
        }
      }
    }
  }
bool _nameMatches(String deviceName, Set<String> names) {
  if (names.contains(deviceName)) return true;

  final shortName = deviceName.contains(':')
      ? deviceName.split(':').last
      : deviceName;

  return names.contains(shortName);
}

Set<String> _sceneOutputNamesFromRawScenes(List<dynamic> rawScenes) {
  final Set<String> used = <String>{};

  for (final scene in rawScenes) {
    if (scene is Map) {
      _collectSceneTargets(scene, used);
    }
  }

  return used;
}

Set<String> _targetsForOneScene(Map scene) {
  final Set<String> used = <String>{};
  _collectSceneTargets(scene, used);
  return used;
}

int _sceneTimeoutSeconds(Map scene, String key) {
  final String mode = (scene['mode'] ?? '').toString();
  final bool sameTime = mode == 'same_time';

  final actions = scene[key];
  if (actions is! List || actions.isEmpty) {
    return 10;
  }

  int sumDelay = 0;
  int maxDelay = 0;

  for (final action in actions) {
    if (action is! Map) continue;

    final int d = int.tryParse(
          (action['delaySec'] ??
                  action['delay'] ??
                  action['afterSec'] ??
                  action['after'] ??
                  '0')
              .toString(),
        ) ??
        0;

    sumDelay += d;
    if (d > maxDelay) maxDelay = d;
  }

  // Sequential scene waits sum of delays.
  // Same-time scene waits only biggest delay.
  final int sceneDelay = sameTime ? maxDelay : sumDelay;

  // Extra time for relay command processing + network delay.
  final int total = sceneDelay + 10;

  // Minimum 10 sec, maximum 1 hour.
  return total.clamp(10, 3600).toInt();
}

void _collectSceneTargets(Map scene, Set<String> used) {
  void collect(dynamic node) {
    if (node is List) {
      for (final item in node) {
        collect(item);
      }
      return;
    }

    if (node is Map) {
      // Most possible scene action output keys
     for (final key in [
        'target',
        'target_output',
        'output',
        'outputName',
        'targetName',
        'deviceName',
        'name',
      ]) {
        final value = node[key];
        if (value is String && value.trim().isNotEmpty) {
          final v = value.trim();

          // Avoid collecting generic action names
          if (v != 'ON' &&
              v != 'OFF' &&
              v != 'AUTO' &&
              v != 'relay' &&
              v != 'pwm' &&
              v != 'analog') {
            used.add(v);
          }
        }
      }

      // Nested actions
      for (final key in [
        'actions',
        'undo',
        'undoActions',
        'outputs',
        'items',
        'children',
      ]) {
        if (node[key] != null) {
          collect(node[key]);
        }
      }
    }
  }

  collect(scene['actions']);
  collect(scene['undo']);
  collect(scene['undoActions']);
  collect(scene['outputs']);
}
  // ... KEEP ALL YOUR OTHER AWESOME V5 CODE EXACTLY THE SAME BELOW THIS ...
Future<void> _fetchDevicesFromServer({bool silent = false}) async {
    try {
      debugPrint('Connecting to board: $_baseUrl');
      // 👇 NEW: Heartbeat - tell board this mobile app is still connected
      await http.get(
        Uri.parse(
          '$_baseUrl/api/status?cid=${Uri.encodeComponent(_clientId)}'
          '&sid=${Uri.encodeComponent(_sessionId)}'
          '&name=${Uri.encodeComponent(_clientName)}',
        ),
      ).timeout(const Duration(seconds: 3));
      final response = await http
          .get(Uri.parse('$_baseUrl/api/load-matrix'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Board returned HTTP ${response.statusCode}');
      }
      
      final Map<String, dynamic> data = json.decode(response.body);
      final Map<String, dynamic> setup = (data['setup'] is Map) ? Map<String, dynamic>.from(data['setup']) : {};

    final Map<String, dynamic> configure = (data['configure'] is Map) ? Map<String, dynamic>.from(data['configure']) : {};
      final Map<String, dynamic> overrides = (configure['overrides'] is Map) ? Map<String, dynamic>.from(configure['overrides']) : {};
      
      final List<dynamic> rawOutputs = (setup['outputs'] is List) ? setup['outputs'] : (data['outputs'] is List ? data['outputs'] : []);
      final List<dynamic> rawEmojis =
    (setup['outputEmojis'] is List) ? setup['outputEmojis'] : [];

final List<dynamic> rawScenes =
    (data['scenes'] is List)
        ? data['scenes']
        : (setup['scenes'] is List)
            ? setup['scenes']
            : ((data['configure'] is Map && data['configure']['scenes'] is List)
                ? data['configure']['scenes']
                : []);
final Set<String> logicOutputNames = _logicOutputNamesFromConfigure(configure);
      final Set<String> sceneOutputNames = _sceneOutputNamesFromRawScenes(rawScenes);
List<dynamic> rawPwmOutputs = [];
List<dynamic> rawAnalogOutputs = [];

try {
  final pwmResponse = await http
      .get(Uri.parse('$_baseUrl/api/load-pwm-analog-outputs'))
      .timeout(const Duration(seconds: 5));

  if (pwmResponse.statusCode == 200) {
    final pwmData = json.decode(pwmResponse.body);

   if (pwmData is Map) {
  if (pwmData['pwmOutputs'] is List) {
    rawPwmOutputs = pwmData['pwmOutputs'];
  }

  if (pwmData['analogOutputs'] is List) {
    rawAnalogOutputs = pwmData['analogOutputs'];
  }
}
  }
} catch (e) {
  debugPrint('PWM load failed: $e');
}

List<String> sliderKeywords = ['fan', 'light', 'mixer', 'blinds', 'dimmer', 'volume'];

      final List<SmartDevice> parsedDevices = rawOutputs.asMap().entries.map((entry) {
        int idx = entry.key;
        var o = entry.value;
        String name = (o is Map && o['name'] != null) ? o['name'].toString() : o.toString();
        
        final bool usedInLogic = _nameMatches(name, logicOutputNames);
        final bool usedInScene = _nameMatches(name, sceneOutputNames);
        // If output is used in Configure logic, default mode is AUTO.
        // If it is not used in Configure logic, it is a simple ON/OFF output.
        String physical = (o is Map && o['physicalState'] != null) ? o['physicalState'].toString() : 'OFF';
        String state = (usedInLogic || usedInScene) ? 'AUTO' : physical;
        if (overrides.containsKey(name)) {
            var ovr = overrides[name];
            if (ovr is Map && ovr['override'] == true) {
                state = ovr['enabled'] == true ? 'ON' : 'OFF';
            }
        }

        bool isLocked = false; // PIN/lock UI disabled

       String emoji = '⚙️';

if (o is Map && o['emoji'] != null && o['emoji'].toString().isNotEmpty) {
  emoji = _safeEmojiForMobile(o['emoji'].toString(), fallback: '⚙️');
} else if (idx < rawEmojis.length && rawEmojis[idx].toString().isNotEmpty) {
  emoji = _safeEmojiForMobile(rawEmojis[idx].toString(), fallback: '⚙️');
}
        return {
  'name': name,
  'emoji': emoji,
  'state': state,
  'physical': physical,
  'isLocked': isLocked,
  'usedInLogic': usedInLogic,
  'usedInScene': usedInScene,
};
      }).where((deviceData) {
        String searchName = deviceData['name'].toString().toUpperCase();
        return searchName.isNotEmpty && !searchName.startsWith('IR') && !searchName.startsWith('TELNET') && !searchName.startsWith('RS232') && !searchName.startsWith('RS485') && !searchName.startsWith('RS422');
      }).map((deviceData) {
        String deviceName = deviceData['name'].toString();
        String searchName = deviceName.toLowerCase();
        bool needsSlider = sliderKeywords.any((keyword) => searchName.contains(keyword));
        String dynamicLabel = (searchName.contains('fan') || searchName.contains('mixer')) ? 'Speed' : 'Level';

        return SmartDevice(
          id: searchName.replaceAll(' ', '_'),
          name: deviceName,
          description: 'Hardware Output',
          iconUrl: deviceData['emoji'].toString(),
          state: deviceData['state'].toString(),
          physicalState: deviceData['physical'].toString(),
          isLockedByOther: false,
          isUsedInLogic: deviceData['usedInLogic'] as bool,
          isUsedInScene: deviceData['usedInScene'] as bool,
          ownerType: (deviceData['usedInLogic'] as bool) ? 'logic' : 'none',
          hasPwm: needsSlider,
          pwmLabel: dynamicLabel,
        );
      }).toList();
final List<SmartDevice> parsedPwmDevices = rawPwmOutputs.map((p) {
  if (p is! Map) {
    return null;
  }

  final String port = (p['port'] ?? '').toString(); // PWM1
  final String pwmName = (p['name'] ?? '').toString(); // Light
  final int defaultDuty = int.tryParse((p['duty'] ?? '50').toString()) ?? 50;

  if (port.isEmpty || pwmName.isEmpty) {
    return null;
  }

  final String fullName = '$port:$pwmName';
final bool usedInLogic = _nameMatches(fullName, logicOutputNames) || _nameMatches(pwmName, logicOutputNames);
final bool usedInScene = _nameMatches(fullName, sceneOutputNames) || _nameMatches(pwmName, sceneOutputNames);
  bool manual = false;
  int liveValue = defaultDuty;

  if (overrides.containsKey(fullName)) {
    final ovr = overrides[fullName];
    if (ovr is Map) {
      manual = ovr['override'] == true;
      if (ovr['value'] != null) {
        liveValue = int.tryParse(ovr['value'].toString()) ?? defaultDuty;
      }
    }
  }

  return SmartDevice(
    id: fullName.toLowerCase().replaceAll(' ', '_').replaceAll(':', '_'),
    name: fullName,
    description: 'PWM Output',
    iconUrl: _safeEmojiForMobile((p['icon'] ?? '⚡').toString(), fallback: '⚡'),
    state: usedInLogic ? (manual ? 'MANUAL' : 'AUTO') : 'MANUAL',
    physicalState: '$liveValue%',
    hasPwm: true,
    pwmValue: liveValue.toDouble(),
    pwmLabel: 'Duty',
    kind: 'pwm',
    port: port,
    isLockedByOther: false,
    isUsedInLogic: usedInLogic,
    isUsedInScene: usedInScene,
    ownerType: usedInLogic ? 'logic' : 'none',
  );
}).whereType<SmartDevice>().toList();

final List<SmartDevice> parsedAnalogDevices = rawAnalogOutputs.map((a) {
  if (a is! Map) {
    return null;
  }

  final String port = (a['port'] ?? '').toString(); // ANA1
  final String analogName = (a['name'] ?? '').toString(); // Volume
  final double defaultVolt =
    double.tryParse((a['voltage'] ?? a['value'] ?? '0').toString()) ?? 0.0;

  if (port.isEmpty || analogName.isEmpty) {
    return null;
  }

  final String fullName = '$port:$analogName';
  final bool usedInLogic = _nameMatches(fullName, logicOutputNames) || _nameMatches(analogName, logicOutputNames);
final bool usedInScene = _nameMatches(fullName, sceneOutputNames) || _nameMatches(analogName, sceneOutputNames);

  bool manual = false;
  double liveVolt = defaultVolt;

  if (overrides.containsKey(fullName)) {
    final ovr = overrides[fullName];
    if (ovr is Map) {
      manual = ovr['override'] == true;

      if (ovr['value'] != null) {
        liveVolt = double.tryParse(ovr['value'].toString()) ?? defaultVolt;
      }
    }
  }

  if (liveVolt < 0.0) liveVolt = 0.0;
  if (liveVolt > 10.0) liveVolt = 10.0;

  return SmartDevice(
    id: fullName.toLowerCase().replaceAll(' ', '_').replaceAll(':', '_'),
    name: fullName,
    description: 'Analog Output',
    iconUrl: _safeEmojiForMobile((a['icon'] ?? '📈').toString(), fallback: '📈'),
    state: usedInLogic ? (manual ? 'MANUAL' : 'AUTO') : 'MANUAL',
    physicalState: '${liveVolt.toStringAsFixed(2)}V',
    hasPwm: true,
    pwmValue: liveVolt,
    pwmLabel: 'Voltage',
    kind: 'analog',
    port: port,
    isLockedByOther: false,
    isUsedInLogic: usedInLogic,
    isUsedInScene: usedInScene,
    ownerType: usedInLogic ? 'logic' : 'none',
  );
}).whereType<SmartDevice>().toList();

   final List<SmartScene> parsedScenes = rawScenes.map((s) {
  if (s is Map) {
    return SmartScene(
      id: (s['id'] ?? s['sceneId'] ?? s['name'] ?? 'scene_x').toString(),
      name: (s['name'] ?? 'Scene').toString(),
      icon: (s['emoji'] ?? s['iconKey'] ?? s['icon'] ?? '⚡').toString(),
      actionTargets: _targetsForOneScene(s),
      runTimeoutSeconds: _sceneTimeoutSeconds(s, 'actions'),
      undoTimeoutSeconds: _sceneTimeoutSeconds(s, 'undo'),
    );
  }

  return SmartScene(
    id: s.toString(),
    name: s.toString(),
    icon: '⚡',
  );
}).toList();

      setState(() {
  _devices = [
   ...parsedDevices,
  ...parsedPwmDevices,
  ...parsedAnalogDevices,
  ];
  _scenes = parsedScenes;
});
      await _loadSavedMemory();

      if (mounted && !silent) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Connected: ${_devices.length} relays, ${_scenes.length} scenes',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}
   } catch (e) {
  debugPrint('API Connection Failed: $e');

  // During background silent refresh, do not wipe the UI for one temporary network error.
  if (silent) return;

  setState(() {
    _devices = [];
    _scenes = [];
  });

  if (mounted && !silent) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Server connected, but parse failed: $e',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
  }
  // --- LOCAL STORAGE LOGIC (THIS WAS MISSING!) ---
// --- LOCAL STORAGE LOGIC (V2) ---
  Future<void> _loadSavedMemory() async {
    _prefs = await SharedPreferences.getInstance();
    
    // 👇 NEW: Load dynamic PWM sliders directly into the devices!
    setState(() {
  for (var device in _devices) {
    if (device.isPwmOutput) {
      device.pwmValue = _prefs.getDouble('${device.name}_pwm') ?? device.pwmValue;
      device.pwmValue = device.pwmValue.clamp(0.0, 100.0);
      device.physicalState = '${device.pwmValue.round()}%';
    }

  if (device.isAnalogOutput) {
  // Only use saved analog value when device is really in MANUAL mode.
  // If it is AUTO, keep the value coming from board/web config.
  if (device.state == 'MANUAL') {
    device.pwmValue = _prefs.getDouble('${device.name}_analog') ?? device.pwmValue;
  } else {
    _prefs.remove('${device.name}_analog');
  }

  device.pwmValue = device.pwmValue.clamp(0.0, 10.0);
  device.physicalState = '${device.pwmValue.toStringAsFixed(2)}V';
}
  }
});

    for (var scene in _scenes) {
      scene.name = _prefs.getString('${scene.id}_name') ?? scene.name;

      // Dynamically load states for whatever devices currently exist
      for (var device in _devices) {
        String? savedState = _prefs.getString('${scene.id}_${device.name}');
        if (savedState != null) {
          scene.savedStates[device.name] = savedState;
        }
      }
    }
    
    debugPrint('💾 LOADED: Custom Scenes and Dynamic Sliders successfully retrieved!');
  }
bool _applyLocksFromStatus(Map<String, dynamic> statusData) {
  // Admin PIN / lock UI is disabled. Do not mark any output as locked.
  bool changed = false;
  for (final device in _devices) {
    if (device.isLockedByOther) {
      device.isLockedByOther = false;
      changed = true;
    }
  }
  return changed;
}

Future<void> _syncActiveSceneFromBoard() async {
  try {
    final statusResponse = await http.get(
      Uri.parse(
        '$_baseUrl/api/status?cid=${Uri.encodeComponent(_clientId)}'
        '&sid=${Uri.encodeComponent(_sessionId)}'
        '&name=${Uri.encodeComponent(_clientName)}',
      ),
    ).timeout(const Duration(seconds: 3));

    if (statusResponse.statusCode != 200) return;

    final decodedStatus = json.decode(statusResponse.body);
    if (decodedStatus is! Map<String, dynamic>) return;

    final String activeSceneId =
        (decodedStatus['activeSceneId'] ?? '').toString();

    String? activeName;
    SmartScene? activeScene;

    if (activeSceneId.isNotEmpty) {
      for (final scene in _scenes) {
        if (scene.id == activeSceneId) {
          activeScene = scene;
          activeName = scene.name;
          break;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _activeScene = activeName;

      for (final device in _devices) {
        if (activeScene != null &&
            _nameMatches(device.name, activeScene.actionTargets)) {
          device.ownerType = 'scene';
          device.ownerName = activeScene.name;
        } else if (device.ownerType == 'scene') {
          device.ownerType = device.isUsedInLogic ? 'logic' : 'none';
          device.ownerName = '';
        }
      }
    });
  } catch (e) {
    debugPrint('Active scene sync failed: $e');
  }
}

  @override
  void dispose() {
    _syncTimer?.cancel();
    _sceneGlowController.dispose(); // 👇 NEW: Kill the engine to save memory
    super.dispose();
  }
  
void _startLiveBackgroundSync() {
  _syncTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
    if (!mounted) return;

    try {
      // Reload config: detects new/removed Configure logic and Scene usage.
      await _fetchDevicesFromServer(silent: true);

      // Reload active scene state from firmware.
      await _syncActiveSceneFromBoard();
    } catch (e) {
      debugPrint('Silent sync failed: $e');
    }
  });
}

Future<bool> sendHardwareCommand(
  SmartDevice device,
  String state, {
  bool force = false,
  bool showPopup = true,
}) async {
  if (device.name == 'Scene Controller') return true;
  if (device.isPwmOutput || device.isAnalogOutput) return true;

  debugPrint('⏳ Sending hardware: ${device.name} -> $state force=$force');

  final bool isOverride = state == 'ON' || state == 'OFF';
  final bool isEnabled = state == 'ON';

  final Map<String, dynamic> overrideData = {
    "override": isOverride,
    "enabled": isEnabled,
  };

  final Map<String, dynamic> payload = {
    "client_id": _clientId,
    "session_id": _sessionId,
    "client_name": _clientName,
    "target_output": device.name,
    "force": force,
    "overrides": {
      device.name: overrideData,
    },
  };

  try {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/apply-runtime-overrides'),
      headers: _headers,
      body: json.encode(payload),
    ).timeout(const Duration(seconds: 3));

    if (response.statusCode == 200 || response.statusCode == 204) {
      debugPrint('✅ Hardware confirmed: ${device.name} -> $state');
      return true;
    }

    if (response.statusCode == 409) {
      throw Exception(
        'This output is controlled by automation/scene. Use Force ON/OFF to take control.',
      );
    }

    throw Exception('Hardware rejected with code: ${response.statusCode}');
  } catch (e) {
    debugPrint('❌ Command Failed: $e');

    if (!mounted) return false;

    if (showPopup) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return false;
  }
}

  Future<bool> sendPwmCommand(
  SmartDevice device,
  double value, {
  bool manual = true,
  bool force = false,
}) async {
  final int duty = value.round().clamp(0, 100);

  Map<String, dynamic> pwmOverride;

  if (manual) {
    pwmOverride = {
      "override": true,
      "value": duty,
    };
  } else {
    pwmOverride = {
      "override": false,
    };
  }

  // Admin PIN disabled: do not send pin in runtime override payload.

  final Map<String, dynamic> payload = {
    "client_id": _clientId,
    "session_id": _sessionId,
    "client_name": _clientName,
    "target_output": device.name,
    "force": force,
    "overrides": {
      device.name: pwmOverride,
    },
  };

  try {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/apply-runtime-overrides'),
      headers: _headers,
      body: json.encode(payload),
    ).timeout(const Duration(seconds: 3));

    if (response.statusCode == 200 || response.statusCode == 204) {
      debugPrint('✅ PWM confirmed: ${device.name} -> ${manual ? "$duty%" : "AUTO"}');
      return true;
    }

    if (response.statusCode == 403) {
      throw Exception('PWM command rejected by firmware lock. Disable the firmware lock check also.');
    }

    throw Exception('PWM command rejected: HTTP ${response.statusCode}');
  } catch (e) {
    debugPrint('❌ PWM command failed: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return false;
  }
}


Future<bool> sendAnalogCommand(
  SmartDevice device,
  double value, {
  bool manual = true,
  bool force = false,
}) async {
  double volt = value.clamp(0.0, 10.0).toDouble();
  volt = double.parse(volt.toStringAsFixed(2));

  Map<String, dynamic> analogOverride;

  if (manual) {
    analogOverride = {
      "override": true,
      "value": volt,
    };
  } else {
    analogOverride = {
      "override": false,
    };
  }

  // Admin PIN disabled: do not send pin in runtime override payload.

  final Map<String, dynamic> payload = {
    "client_id": _clientId,
    "session_id": _sessionId,
    "client_name": _clientName,
    "target_output": device.name,
    "force": force,
    "overrides": {
      device.name: analogOverride,
    },
  };

  try {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/apply-runtime-overrides'),
      headers: _headers,
      body: json.encode(payload),
    ).timeout(const Duration(seconds: 3));

    if (response.statusCode == 200 || response.statusCode == 204) {
      debugPrint('✅ Analog confirmed: ${device.name} -> ${manual ? "${volt}V" : "AUTO"}');
      return true;
    }

    if (response.statusCode == 403) {
      throw Exception('Analog command rejected by firmware lock. Disable the firmware lock check also.');
    }

    throw Exception('Analog command rejected: HTTP ${response.statusCode}');
  } catch (e) {
    debugPrint('❌ Analog command failed: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return false;
  }
}


  // --- SCENE AUTOMATION LOGIC (WITH ROLLBACK) ---
// 👇 NEW: The hidden variable that remembers the room before a scene starts
  final Map<String, String> _preSceneSnapshot = {};
SmartDevice? _findDeviceBySceneTarget(String target) {
  for (final device in _devices) {
    if (_nameMatches(device.name, {target})) {
      return device;
    }
  }
  return null;
}

List<SmartDevice> _sceneManualOverrideDevices(SmartScene scene) {
  final List<SmartDevice> blocked = [];

  for (final target in scene.actionTargets) {
    final device = _findDeviceBySceneTarget(target);
    if (device == null) continue;

    final bool manualOverride =
        device.state == 'ON' ||
        device.state == 'OFF' ||
        device.state == 'MANUAL' ||
        device.ownerType == 'force';

    if (manualOverride && !device.isSceneOwned) {
      blocked.add(device);
    }
  }

  return blocked;
}

void _showSceneAutoRequiredDialog(SmartScene scene, List<SmartDevice> blocked) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Set AUTO first',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Cannot run "${scene.name}". These outputs are manually overridden:\n\n'
          '${blocked.map((d) => d.name).join('\n')}\n\n'
          'Open each output and tap AUTO / Release to Scene first.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
  // --- V2 LIVE SCENE ACTIVATION ---
  Future<void> activateSceneLogic(String sceneName) async {
    debugPrint('🎬 Activating Scene: $sceneName');
    
    // 1. Secretly snapshot the room, but ONLY if we aren't already in a scene!
    if (_activeScene == null) {
      _preSceneSnapshot.clear();
      for (var device in _devices) {
        _preSceneSnapshot[device.name] = device.state;
      }
    }

    final scene = _scenes.firstWhere((s) => s.name == sceneName);
    final blockedDevices = _sceneManualOverrideDevices(scene);
if (blockedDevices.isNotEmpty) {
  _showSceneAutoRequiredDialog(scene, blockedDevices);
  return;
}
    final List<String> backupStates = _devices.map((d) => d.state).toList();

    setState(() {
      _activeScene = sceneName; 
      // Apply the macro to the room
      for (var device in _devices) {
        if (scene.savedStates.containsKey(device.name)) {
          device.state = scene.savedStates[device.name]!;
        }
      }
    });

    // 👇 LIVE API: Trigger the scene on the physical hardware!
    bool success = false;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/scene/run'), // Note: use /api/scene/undo for deactivateSceneLogic
        headers: _headers,
        // 👇 NEW: Inject the Client ID into the Scene Payload
        body: json.encode({
          "id": scene.id,
          "client_id": _clientId,
          "session_id": _sessionId,
          "client_name": _clientName,
        }),
      ).timeout(Duration(seconds: scene.runTimeoutSeconds));

      if (response.statusCode == 200 || response.statusCode == 204) {
        success = true;
      }
    } catch (e) {
      debugPrint('❌ Scene Trigger Failed: $e');
    }

    if (!success) {
      debugPrint('⚠️ Scene failed. Rolling back room to previous state.');
      setState(() {
        _activeScene = null; 
        for (int i = 0; i < _devices.length; i++) {
          _devices[i].state = backupStates[i];
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection Lost: Could not activate ${scene.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
  setState(() {
    for (final device in _devices) {
      if (_nameMatches(device.name, scene.actionTargets)) {
        device.ownerType = 'scene';
        device.ownerName = scene.name;
      }
    }
  });

  for (var device in _devices) {
    await _prefs.setString(device.name, device.state);
  }
}
  }

  // --- V2 LIVE SCENE DEACTIVATION (UNDO) ---
  Future<void> deactivateSceneLogic() async {
    debugPrint('🎬 Turning Scene OFF. Restoring previous room layout...');

    final String? lastSceneName = _activeScene;
    // Find the scene we are turning off so we can grab its ID
    final scene = _scenes.firstWhere((s) => s.name == lastSceneName, orElse: () => _scenes.first);

    setState(() {
      _activeScene = null; 
      
      // Instantly restore every device to the hidden snapshot
      for (var device in _devices) {
        if (_preSceneSnapshot.containsKey(device.name)) {
          device.state = _preSceneSnapshot[device.name]!;
        }
      }
    });

    // 👇 LIVE API: Tell the RP2350B we cancelled the macro
    bool success = false;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/scene/undo'),
        headers: _headers,
        body: json.encode({
  "id": scene.id,
  "client_id": _clientId,
  "session_id": _sessionId,
  "client_name": _clientName,
}),
      ).timeout(Duration(seconds: scene.undoTimeoutSeconds));

      if (response.statusCode == 200 || response.statusCode == 204) {
        success = true;
      }
    } catch (e) {
      debugPrint('❌ Scene Undo Failed: $e');
    }

    if (success) {
  setState(() {
    for (final device in _devices) {
      if (device.ownerType == 'scene' && device.ownerName == scene.name) {
        device.ownerType = device.isUsedInLogic ? 'logic' : 'none';
        device.ownerName = '';
      }
    }
  });

  for (var device in _devices) {
    await _prefs.setString(device.name, device.state);
  }
}
  }

Widget _buildGridHardwareNode(SmartDevice device) {
  final double normalized = device.isPwmOutput
      ? (device.pwmValue / 100.0).clamp(0.0, 1.0)
      : (device.pwmValue / 10.0).clamp(0.0, 1.0);

  // ✅ Icon brightness follows PWM duty / analog voltage.
  final double iconOpacity = (0.35 + (normalized * 0.65)).clamp(0.35, 1.0);

  final bool isManual = device.state == 'MANUAL';
  final Color activeBorderColor = isManual ? Colors.blueAccent : Colors.transparent;

  return Column(
    children: [
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _showMacUiRadialSlider(context, device);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 65,
          height: 65,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: activeBorderColor.withAlpha(180),
              width: isManual ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isManual ? Colors.blueAccent : Colors.black).withAlpha(25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: iconOpacity,
               child: Text(
  device.iconUrl.isNotEmpty
      ? device.iconUrl
      : (device.isPwmOutput ? '⚡' : '📈'),
  style: const TextStyle(fontSize: 26),
),
              ),
              Positioned(
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(61),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    device.isPwmOutput
                        ? '${device.pwmValue.round()}%'
                        : '${device.pwmValue.toStringAsFixed(1)}V',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              if (device.isUsedInLogic)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withAlpha(180),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: Text(
  '${device.iconUrl} ${device.name.split(':').last}',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}


void _showMacUiRadialSlider(BuildContext context, SmartDevice device) {
  // Simple timestamp tracking to throttle network operations down to ~every 80ms during active live dragging
  int lastSentTimestamp = 0;
final bool forceManual = device.isProtectedOutput;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        double currentVal = device.pwmValue;
        double maxLimit = device.isPwmOutput ? 100.0 : 10.0;

        return StatefulBuilder(
          builder: (context, setPopupState) {
            double percentage = currentVal / maxLimit;

            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  width: 280,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 12))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
  '${device.iconUrl} ${device.name.split(':').last}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.isPwmOutput ? 'Live Duty Cycle Control' : 'Live Analog Voltage Control',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 24),
                      
                      // 👇 LIVE DRAG INTERACTION ENGAGEMENT EYE
                      GestureDetector(
                        onPanUpdate: (details) async {
                          RenderBox renderBox = context.findRenderObject() as RenderBox;
                          Offset center = renderBox.size.center(Offset.zero);
                          Offset localPos = renderBox.globalToLocal(details.globalPosition);
                          
                          double radians = atan2(localPos.dy - center.dy, localPos.dx - center.dx);
                          double angle = radians * (180 / pi);
                          if (angle < 0) angle += 360;

                          double normalizedProgress = ((angle + 90) % 360) / 360;
                          
                          double targetVal = normalizedProgress * maxLimit;

                          setPopupState(() {
                            currentVal = targetVal;
                            setState(() {
                              device.pwmValue = currentVal;
                              device.state = 'MANUAL';
                              device.physicalState = device.isPwmOutput 
                                  ? '${currentVal.round()}%' 
                                  : '${currentVal.toStringAsFixed(2)}V';
                            });
                          });

                          // ⚡️ LIVE COMMUNICATION PIPE (Throttled execution to protect hardware buffers)
                          int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
                          if (currentTimestamp - lastSentTimestamp > 80) {
                            lastSentTimestamp = currentTimestamp;
                            try {
                              if (device.isPwmOutput) {
                                await sendPwmCommand(device, currentVal, manual: true, force: forceManual);
                                await _prefs.setDouble('${device.name}_pwm', currentVal);
                              } else {
                                await sendAnalogCommand(device, currentVal, manual: true, force: forceManual);
                                await _prefs.setDouble('${device.name}_analog', currentVal);
                              }
                            } catch (e) {
                              debugPrint("Live adjustment sync failure: $e");
                            }
                          }
                        },
                        // Synchronize persistent memory values on final drag release
                        onPanEnd: (_) async {
                          if (device.isPwmOutput) {
                            await sendPwmCommand(device, currentVal, manual: true, force: forceManual);
                            await _prefs.setDouble('${device.name}_pwm', currentVal);
                          } else {
                            await sendAnalogCommand(device, currentVal, manual: true, force: forceManual);
                            await _prefs.setDouble('${device.name}_analog', currentVal);
                          }
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 150,
                              height: 150,
                              child: CircularProgressIndicator(
                                value: percentage.clamp(0.0, 1.0),
                                strokeWidth: 12,
                                backgroundColor: Colors.white10,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                              ),
                            ),
                            Column(
                              children: [
                                Text(
                                  device.isPwmOutput 
                                      ? '${currentVal.round()}%' 
                                      : '${currentVal.toStringAsFixed(2)}V',
                                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  device.isPwmOutput ? 'LIVE LEVEL' : 'LIVE VOLTS',
                                  style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // ✅ AUTO is shown only when this PWM/Analog output is used in Configure logic.
                      Row(
                        children: [
                          if (device.isUsedInLogic) ...[
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blueAccent,
                                  side: const BorderSide(color: Colors.blueAccent, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: () async {
                                  Navigator.pop(context);
                                  if (device.isPwmOutput) {
                                    final ok = await sendPwmCommand(device, currentVal, manual: false, force: false);
                                    if (ok) setState(() => device.state = 'AUTO');
                                  } else {
                                    final ok = await sendAnalogCommand(device, currentVal, manual: false, force: false);
                                    if (ok) setState(() => device.state = 'AUTO');
                                  }
                                },
                                child: const Text('AUTO MODE', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF333333),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final scaleCurve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInBack,
        );
        
        return ScaleTransition(
          scale: scaleCurve,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    ),
  );
}


Widget _buildMainContent(double screenWidth, bool isMobile) {
  double sceneWidth = isMobile ? (screenWidth - 32 - 24) / 3 : 120;

  final pwmDevices = _devices.where((device) => device.isPwmOutput).toList();
  final analogDevices = _devices.where((device) => device.isAnalogOutput).toList();
  final relayDevices = _devices.where((device) => !device.isPwmOutput && !device.isAnalogOutput).toList();

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_scenes.isNotEmpty) ...[
          const Text('Scenes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 12, runSpacing: 12,
              alignment: WrapAlignment.center,
              children: _scenes.map((scene) => _buildSceneButton(scene, sceneWidth)).toList(),
            ),
          ),
          const SizedBox(height: 30),
        ],
        
        const Text('Appliance Grid', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        if (relayDevices.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: const Text('Awaiting Appliances...', style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: relayDevices.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isMobile ? 4 : 6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              mainAxisExtent: 110,
            ),
            itemBuilder: (context, index) => _buildGridApplianceNode(relayDevices[index]),
          ),
        
        const SizedBox(height: 30),
        
        // 👇 NEW: Clean Launcher Grid for Adjustable Hardware Outputs
        const Text('Hardware Output', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        if (pwmDevices.isEmpty && analogDevices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No adjustable hardware configured.', style: TextStyle(color: Colors.grey)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pwmDevices.length + analogDevices.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isMobile ? 4 : 6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              mainAxisExtent: 110,
            ),
            itemBuilder: (context, index) {
              final isPwm = index < pwmDevices.length;
              final device = isPwm ? pwmDevices[index] : analogDevices[index - pwmDevices.length];
              return _buildGridHardwareNode(device);
            },
          ),
        const SizedBox(height: 32),
        ],
      ),
    );
  }
@override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Room Controls', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        elevation: 4, 
        actions: [
          // 👇 FIXED: The Hub Switcher button is now safely inside the main class!
          IconButton(
            icon: const Icon(Icons.wifi_find_rounded),
            tooltip: 'Switch Smart Hub',
            onPressed: () {
              // Now it can safely cancel the timer!
              _syncTimer?.cancel();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HubDiscoveryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'System Settings',
            onPressed: () {
              Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsScreen(
                hubIp: _baseUrl, 
                devices: _devices, 
                scenes: _scenes
               ),
             ),
            );
          },
        ),
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Toggle Theme',
            onPressed: () => SmartRelayApp.of(context).toggleTheme(),
          ),
        ],
      ),
      body: _buildMainContent(screenWidth, isMobile),
    );
  }

  // --- HELPER FUNCTIONS ---

Widget _buildSceneButton(SmartScene scene, double width) {
  bool isActive = _activeScene == scene.name;
  bool isHovered = _hoveredScene == scene.name;

  return MouseRegion(
    onEnter: (_) => setState(() => _hoveredScene = scene.name),
    onExit: (_) => setState(() => _hoveredScene = null),
    child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (_activeScene == scene.name) {
          deactivateSceneLogic();
        } else {
          activateSceneLogic(scene.name);
        }
      },
      // 👇 NEW: AnimatedScale gives a subtle "press down" effect when tapped
      child: AnimatedScale(
        scale: isActive ? 0.96 : 1.0, 
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: width,
          height: 105,
          decoration: BoxDecoration(
            // 👇 NEW: Semi-transparent when active for the glass effect
            color: isActive 
                ? Colors.blueAccent.withValues(alpha: 0.25) 
                : (isHovered ? Theme.of(context).hoverColor : Theme.of(context).cardColor),
            borderRadius: BorderRadius.circular(16),
            border: isActive ? Border.all(color: Colors.blueAccent.withValues(alpha: 0.5), width: 1.5) : null,
            boxShadow: [
              if (!isActive)
                BoxShadow(
                  color: Colors.grey.withValues(alpha: isHovered ? 0.4 : 0.2),
                  blurRadius: isHovered ? 12 : 8,
                  offset: Offset(0, isHovered ? 6 : 4),
                )
            ],
          ),
          // 👇 NEW: The Frosted Glass Engine
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: isActive ? 10.0 : 0.0, sigmaY: isActive ? 10.0 : 0.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(scene.icon, style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  Text(
                    scene.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.blueAccent : Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}


 Widget _buildGridApplianceNode(SmartDevice device) {
  final String currentState = device.state;
  final bool canAuto = device.isUsedInLogic || device.isUsedInScene;
  final bool isPhysicalOn = device.physicalState == 'ON';
  final bool isAuto = canAuto && currentState == 'AUTO';
  final bool isOnNow =
      currentState == 'ON' || (isAuto && isPhysicalOn) || (device.isFreeOutput && isPhysicalOn);

  Color boxColor = Theme.of(context).cardColor;
  Color activeBorderColor = Colors.transparent;

  if (device.isSceneOwned) {
    activeBorderColor = Colors.purpleAccent;
  } else if (currentState == 'ON') {
    activeBorderColor = Colors.green;
  } else if (currentState == 'OFF') {
    activeBorderColor = Colors.orange;
  } else if (isAuto && isPhysicalOn) {
    activeBorderColor = Colors.blueAccent;
  }

  final double iconOpacity = isOnNow ? 1.0 : 0.35;

  return Column(
    children: [
      GestureDetector(
        onTap: () async {
          HapticFeedback.lightImpact();

          if (device.isFreeOutput) {
            // Free relay: simple ON/OFF only
            final String targetState = isOnNow ? 'OFF' : 'ON';

            final bool success = await sendHardwareCommand(
              device,
              targetState,
              force: false,
            );

            if (success) {
              setState(() {
                device.state = targetState;
                device.physicalState = targetState;
                device.ownerType = 'none';
                device.ownerName = '';
              });

              await _prefs.setString(device.name, targetState);
            }
          } else {
            // Logic/Scene output: do NOT direct toggle.
            // User must choose Force ON / Force OFF / AUTO.
            _showAutomationContextMenu(context, device);
          }
        },
        onLongPress: () {
          HapticFeedback.vibrate();
          _showAutomationContextMenu(context, device);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 65,
          height: 65,
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: activeBorderColor.withAlpha(180),
              width: activeBorderColor != Colors.transparent ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (activeBorderColor != Colors.transparent
                        ? activeBorderColor
                        : Colors.black)
                    .withAlpha(25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: iconOpacity,
                child: Text(
                  device.iconUrl.isNotEmpty ? device.iconUrl : '⚙️',
                  style: const TextStyle(fontSize: 28),
                ),
              ),

              if (device.isUsedInLogic)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isAuto
                          ? (isPhysicalOn
                              ? Colors.green
                              : Colors.blueAccent.withAlpha(100))
                          : Colors.blueAccent.withAlpha(180),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

              if (device.isSceneOwned)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.purpleAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: Text(
          device.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}


// 👇 NEW: Custom notification pop-up built for automated task assignment transitions
void _showAutomationContextMenu(BuildContext context, SmartDevice device) {
  Future<void> setMode(String mode, {required bool force}) async {
    Navigator.pop(context);

    final bool success = await sendHardwareCommand(
      device,
      mode,
      force: force,
    );

    if (success) {
      setState(() {
        device.state = mode;

        if (mode == 'ON' || mode == 'OFF') {
          device.physicalState = mode;
          device.ownerType = force ? 'force' : 'none';
          device.ownerName = force ? _clientName : '';
        }

        if (mode == 'AUTO') {
          device.ownerType = device.isUsedInLogic ? 'logic' : 'none';
          device.ownerName = '';
        }
      });

      await _prefs.setString(device.name, mode);
    }
  }

  showDialog(
    context: context,
    builder: (BuildContext context) {
      final bool free = device.isFreeOutput;

      return AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          device.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current State: ${device.state}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
         

            if (device.isSceneOwned)
              Text(
                'Owned by Scene: ${device.ownerName}',
                style: const TextStyle(color: Colors.purpleAccent, fontSize: 13),
              ),

            if (device.isUsedInLogic || device.isUsedInScene)
              const Text(
                'Used in Configure Logic',
                style: TextStyle(color: Colors.blueAccent, fontSize: 13),
              ),

            if (device.isUsedInScene && !device.isSceneOwned)
              const Text(
                'Used in Scene',
                style: TextStyle(color: Colors.purpleAccent, fontSize: 13),
              ),

            const Divider(color: Colors.white24, height: 20),

            ListTile(
              dense: true,
              leading: const Icon(Icons.power_settings_new, color: Colors.green),
              title: Text(
                free ? 'ON' : 'Force ON',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => setMode('ON', force: !free),
            ),

            ListTile(
              dense: true,
              leading: const Icon(Icons.power_off, color: Colors.orange),
              title: Text(
                free ? 'OFF' : 'Force OFF',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => setMode('OFF', force: !free),
            ),

           if (device.isUsedInLogic || device.isUsedInScene)
  ListTile(
    dense: true,
    leading: const Icon(Icons.hdr_auto_rounded, color: Colors.blueAccent),
    title: Text(
      device.isUsedInLogic ? 'Reset to AUTO Logic' : 'Release to Scene AUTO',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    ),
    subtitle: Text(
      device.isUsedInLogic
          ? 'Let Configure logic control this output'
          : 'Allow Scene to control this output',
      style: const TextStyle(color: Colors.grey, fontSize: 11),
    ),
    onTap: () => setMode('AUTO', force: false),
  ),
          ],
        ),
      );
    },
  );
}
  // --- V2 MACRO BUILDER MENU ---
  // --- V2 MACRO BUILDER MENU (WITH NAMING) ---
}
// --- V2 DYNAMIC SYSTEM DIAGNOSTICS SCREEN ---
class SystemStatusScreen extends StatelessWidget {
  final List<SmartScene> scenes;
  final List<SmartDevice> devices;

  const SystemStatusScreen({
    super.key, 
    required this.scenes,
    required this.devices,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 👇 FIXED: We removed the wrong buttons and restored the clean Diagnostics App Bar!
      appBar: AppBar(
        title: const Text('Network Diagnostics', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Hardware Nodes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 12),
          
          // 👇 DYNAMIC GENERATOR: Loops through every device on the network
          ...devices.map((device) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  // 👇 Changes the router icon to Red if the device drops offline!
                  decoration: BoxDecoration(color: device.isOnline ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(Icons.router, color: device.isOnline ? Colors.green : Colors.red),
                ),
                title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                
                // 👇 NEW: Dynamically displays the Room Location!
                subtitle: Text('Room: ${device.room} • Type: ${device.hasPwm ? 'Variable' : 'Relay'}'),
                
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 👇 NEW: Dynamically shows green ONLINE or red OFFLINE!
                    Text(
                      device.isOnline ? 'ONLINE' : 'OFFLINE', 
                      style: TextStyle(
                        color: device.isOnline ? Colors.green : Colors.red, 
                        fontWeight: FontWeight.bold, 
                        fontSize: 12
                      )
                    ),
                    Text(device.isOnline ? 'Ping: 12ms' : 'No Signal', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 24),
          const Text('Memory Usage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 12),
          
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.memory, color: Colors.orange),
              title: const Text('Saved Macros (Scenes)'),
              trailing: Text('${scenes.where((s) => s.savedStates.isNotEmpty).length} / ${scenes.length} Slots Used', 
                style: const TextStyle(fontWeight: FontWeight.bold)
              ),
            ),
          )
        ],
      ),
    );
  }
}
// --- UNIVERSAL SMART ANIMATION WIDGET ---
class AnimatedApplianceIcon extends StatefulWidget {
  final String deviceName;
  final String emojiIcon; // 👇 Changed from IconData to String
  final bool isOn;
  final Color color;

  const AnimatedApplianceIcon({
    super.key, 
    required this.deviceName, 
    required this.emojiIcon, // 👇 Updated here
    required this.isOn, 
    required this.color
  });

  @override
  State<AnimatedApplianceIcon> createState() => _AnimatedApplianceIconState();
}
// --- NEW: PREMIUM TACTILE BUTTON WIDGET ---
class TactileOptionButton extends StatefulWidget {
  final String label;
  final Color activeColor;
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onTap;

  const TactileOptionButton({
    super.key,
    required this.label,
    required this.activeColor,
    required this.isActive,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  State<TactileOptionButton> createState() => _TactileOptionButtonState();
}

class _TactileOptionButtonState extends State<TactileOptionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      // 👇 FIXED: Removed the '_' because onTapCancel takes zero arguments
      onTapCancel: () => setState(() => _isPressed = false), 
      
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0, // Shrinks by 10% when pressed
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: widget.isActive ? widget.activeColor.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isActive ? widget.activeColor.withValues(alpha: 0.5) : Colors.transparent,
            )
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: widget.isDisabled 
                  ? Colors.grey.withValues(alpha: 0.3) 
                  : (widget.isActive ? widget.activeColor : Colors.grey),
              fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w600,
              fontSize: 13,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _AnimatedApplianceIconState extends State<AnimatedApplianceIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);

    // Creates a smooth 15% scale-up for the lightbulb
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isOn) _startAnimation();
  }

  void _startAnimation() {
    if (widget.deviceName == 'Fan') {
      _controller.duration = const Duration(milliseconds: 1200);
      _controller.repeat(); // Continuous spin
    } else {
      _controller.duration = const Duration(milliseconds: 1500);
      _controller.repeat(reverse: true); // Breathing in and out
    }
  }

  @override
  void didUpdateWidget(AnimatedApplianceIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOn && !oldWidget.isOn) {
      _startAnimation();
    } else if (!widget.isOn && oldWidget.isOn) {
      // Smoothly wind down instead of instantly freezing
      _controller.animateTo(0, duration: const Duration(milliseconds: 400)); 
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. FAN LOGIC: Spinning
    if (widget.deviceName == 'Fan') {
      return RotationTransition(
        turns: _controller,
        child: Text(widget.emojiIcon, style: const TextStyle(fontSize: 26))
      );
    }

    // 2. MAIN LIGHT LOGIC: Soft Scaling Pulse + Glow
    if (widget.deviceName == 'Main Light') {
      return ScaleTransition(
        scale: widget.isOn ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              if (widget.isOn)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4), // Soft glowing aura
                  blurRadius: 12,
                  spreadRadius: 2,
                )
            ],
          ),
          child: Text(widget.emojiIcon, style: const TextStyle(fontSize: 26))
        ),
      );
    }

    // 3. TV & PROJECTOR LOGIC: Cinematic Screen Shimmer
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              if (widget.isOn)
                BoxShadow(
                  // The glow pulses brighter and dimmer with the animation controller
                  color: widget.color.withValues(alpha: 0.15 + (_controller.value * 0.2)), 
                  blurRadius: 8 + (_controller.value * 6),
                  spreadRadius: 1 + (_controller.value * 2),
                )
            ],
          ),
          child: Text(widget.emojiIcon, style: const TextStyle(fontSize: 26))
        );
      },
    );
  }
}
// ==========================================
// 👇 PASTE EVERYTHING BELOW AT THE VERY BOTTOM OF YOUR FILE
// ==========================================

// --- THE PASSIVE UDP LISTENER ENGINE ---
class UdpBroadcastListener {
  RawDatagramSocket? _udpSocket;

  Future<void> startListening(Function(String name, String ip) onHubFound) async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888);
      _udpSocket!.broadcastEnabled = true;

      debugPrint('🎧 Listening for RP2350B Broadcasts on port 8888...');

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = _udpSocket!.receive();
          
          if (datagram != null) {
            String message = utf8.decode(datagram.data);
            debugPrint('📡 Broadcast intercepted: $message');

            try {
              final data = json.decode(message);
              if (data.containsKey('ip') && data.containsKey('name')) {
                onHubFound(data['name'], 'http://${data['ip']}');
              }
           } catch (e) {
  debugPrint('Failed to parse broadcast JSON: $e');
}
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to bind UDP socket: $e');
    }
  }

  void stopListening() {
    _udpSocket?.close();
    debugPrint('🛑 Stopped listening for broadcasts.');
  }
}

// --- THE UPGRADED HUB DISCOVERY UI SCREEN (AUTO + MANUAL) ---
class HubDiscoveryScreen extends StatefulWidget {
  const HubDiscoveryScreen({super.key});

  @override
  State<HubDiscoveryScreen> createState() => _HubDiscoveryScreenState();
}

class _HubDiscoveryScreenState extends State<HubDiscoveryScreen> {
  final UdpBroadcastListener _listener = UdpBroadcastListener();
  final Map<String, String> _discoveredHubs = {}; 
  
  // 👇 NEW: Controller for manual IP entry
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  void _startScanning() {
    _listener.startListening((name, ip) {
      if (mounted) {
        setState(() {
          _discoveredHubs[name] = ip;
        });
      }
    });
  }

  @override
  void dispose() {
    _listener.stopListening();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connectToHub(String name, String rawIp) async {
    _listener.stopListening();
    
    // Ensure the IP has http:// formatted correctly
    String finalIp = rawIp.startsWith('http') ? rawIp : 'http://$rawIp';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_hub_ip', finalIp);
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ControlPanelScreen(hubIp: finalIp),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Network Connection', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- MANUAL CONNECTION SECTION ---
            const Text('Manual Connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: TextField(
                controller: _ipController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'e.g. 192.168.1.27',
                  prefixIcon: const Icon(Icons.link, color: Colors.blueAccent),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.blueAccent),
                    onPressed: () {
                      if (_ipController.text.isNotEmpty) {
                        _connectToHub('Manual Hub', _ipController.text.trim());
                      }
                    },
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) _connectToHub('Manual Hub', value.trim());
                },
              ),
            ),
            
            const SizedBox(height: 40),
            
            // --- AUTO DISCOVERY SECTION ---
            const Row(
              children: [
                SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                ),
                SizedBox(width: 12),
                Text('Auto-Discovering Hubs...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Looking for local hardware broadcasts.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            
            if (_discoveredHubs.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _discoveredHubs.length,
                  itemBuilder: (context, index) {
                    String hubName = _discoveredHubs.keys.elementAt(index);
                    String hubIp = _discoveredHubs.values.elementAt(index);
                    
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.router, color: Colors.white)),
                        title: Text(hubName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        subtitle: Text(hubIp, style: const TextStyle(color: Colors.grey)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _connectToHub(hubName, hubIp),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
class SettingsScreen extends StatefulWidget {
  final String hubIp;
  final List<SmartDevice> devices;
  final List<SmartScene> scenes;

  const SettingsScreen({
    super.key, 
    required this.hubIp,
    required this.devices,
    required this.scenes,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 👇 RESTORED: The function to wipe memory and disconnect!
  Future<void> _disconnectHub() async {
    HapticFeedback.heavyImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_hub_ip'); // Wipe from memory

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HubDiscoveryScreen()),
        (Route<dynamic> route) => false, // Clears the entire navigation stack
      );
    }
  }

  // 👇 RESTORED: The function to clean up memory when the screen closes
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Security/Admin PIN section removed.
          // All users can control relay/PWM/analog outputs directly.

          // --- HUB MANAGEMENT SECTION ---
          const Text('Hub Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 12),
          

          // Disconnect Button Only
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Colors.red.shade100, child: Icon(Icons.link_off, color: Colors.red.shade900)),
              title: const Text('Disconnect Hub', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              subtitle: Text(widget.hubIp),
              onTap: _disconnectHub, // Works perfectly now!
            ),
          ),
        ],
      ),
    );
  }
}