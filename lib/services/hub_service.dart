import 'package:shared_preferences/shared_preferences.dart';

class HubService {
  static Future<void> saveActiveHubIp(String rawIp) async {
  String finalIp = rawIp.startsWith('http')
      ? rawIp
      : 'http://$rawIp';

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('active_hub_ip', finalIp);
}

}