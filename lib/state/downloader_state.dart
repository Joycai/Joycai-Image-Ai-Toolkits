import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../services/web_scraper_service.dart';

class DownloaderState extends ChangeNotifier {
  String url = '';
  String requirement = '';
  String cookies = '';
  String prefix = 'download';
  String manualHtml = '';
  bool isManualHtml = false;
  List<DiscoveredImage> discoveredImages = [];
  List<String> logs = [];
  int? selectedModelPk;
  
  List<Map<String, dynamic>> cookieHistory = [];

  Future<void> loadCookieHistory() async {
    cookieHistory = await DatabaseService().getDownloaderCookies();
    notifyListeners();
  }

  Future<void> saveCookie(String host, String cookieValue) async {
    if (host.isEmpty || cookieValue.isEmpty) return;
    await DatabaseService().saveDownloaderCookie(host, cookieValue);
    await loadCookieHistory();
  }

  void setState({
    String? url,
    String? requirement,
    String? cookies,
    String? prefix,
    String? manualHtml,
    bool? isManualHtml,
    List<DiscoveredImage>? discoveredImages,
    int? selectedModelPk,
  }) {
    if (url != null) this.url = url;
    if (requirement != null) this.requirement = requirement;
    if (cookies != null) this.cookies = cookies;
    if (prefix != null) this.prefix = prefix;
    if (manualHtml != null) this.manualHtml = manualHtml;
    if (isManualHtml != null) this.isManualHtml = isManualHtml;
    if (discoveredImages != null) this.discoveredImages = discoveredImages;
    if (selectedModelPk != null) this.selectedModelPk = selectedModelPk;
    notifyListeners();
  }

  void addLog(String msg) {
    logs.add('[${DateTime.now().toIso8601String().split('T').last.substring(0, 8)}] $msg');
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  void reset() {
    discoveredImages = [];
    logs.clear();
    notifyListeners();
  }

  void notify() {
    notifyListeners();
  }
}
