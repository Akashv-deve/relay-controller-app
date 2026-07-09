class SmartScene {
  final String id;
  String name;
  String icon;

  final Set<String> actionTargets;

  // Dynamic wait time based on scene configured delays
  final int runTimeoutSeconds;
  final int undoTimeoutSeconds;

  Map<String, String> savedStates;

  SmartScene({
    required this.id,
    required this.name,
    required this.icon,
    Set<String>? actionTargets,
    this.runTimeoutSeconds = 10,
    this.undoTimeoutSeconds = 10,
  })  : actionTargets = actionTargets ?? <String>{},
        savedStates = {};
}