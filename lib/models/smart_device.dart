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