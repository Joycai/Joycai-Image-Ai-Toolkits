import 'package:flutter/material.dart';

import '../services/db/repositories/cookie_repository.dart';
import '../services/media/web_scraper_service.dart';

class DownloaderState extends ChangeNotifier {
  String url = '';
  String requirement = '';
  String cookies = '';
  String prefix = 'download';
  String manualHtml = '';
  bool isManualHtml = false;
  List<DiscoveredImage> discoveredImages = [];
  List<String> logs = [];
  int? selectedModelDbId;

  /// True while [analyze] is running. Lives here (not in the screen widget)
  /// so navigating away and back doesn't lose the in-flight analysis: the
  /// main navigation swaps screens instead of using an IndexedStack, so the
  /// screen State is disposed on every switch.
  bool isAnalyzing = false;

  List<Map<String, dynamic>> cookieHistory = [];

  /// How long cookies are remembered (S3). Loaded with the history.
  CookieRetention cookieRetention = CookieRepository.defaultRetention;

  /// Runs the image discovery and stores the results on this state object,
  /// regardless of whether the downloader screen is still mounted. Rethrows
  /// failures so a still-mounted screen can surface a snackbar; the error is
  /// always recorded in [logs] either way.
  Future<void> analyze() async {
    if (isAnalyzing) return;
    final modelId = selectedModelDbId;
    if (modelId == null) return;

    isAnalyzing = true;
    reset();
    addLog('Starting analysis...');

    try {
      final results = await WebScraperService().discoverImages(
        url: url,
        requirement: requirement,
        modelIdentifier: modelId,
        cookies: cookies,
        manualHtml: isManualHtml ? manualHtml : null,
        onLog: addLog,
      );

      discoveredImages = results;
      if (results.isEmpty) {
        addLog('Analysis finished, but no matching images were found.');
      } else {
        addLog('Found ${results.length} images.');
      }

      if (results.isNotEmpty && cookies.isNotEmpty) {
        try {
          final host = Uri.parse(url).host;
          if (host.isNotEmpty) await saveCookie(host, cookies);
        } catch (_) {}
      }
    } catch (e) {
      addLog('Error: $e');
      rethrow;
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }

  Future<void> loadCookieHistory() async {
    final repo = CookieRepository();
    cookieRetention = await repo.retention();
    cookieHistory = await repo.list();
    notifyListeners();
  }

  Future<void> saveCookie(String host, String cookieValue) async {
    if (host.isEmpty || cookieValue.isEmpty) return;
    await CookieRepository().save(host, cookieValue);
    await loadCookieHistory();
  }

  Future<void> setCookieRetention(CookieRetention retention) async {
    await CookieRepository().setRetention(retention);
    await loadCookieHistory();
  }

  Future<void> forgetCookie(String host) async {
    await CookieRepository().delete(host);
    await loadCookieHistory();
  }

  Future<void> clearCookieHistory() async {
    await CookieRepository().clear();
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
    int? selectedModelDbId,
  }) {
    if (url != null) this.url = url;
    if (requirement != null) this.requirement = requirement;
    if (cookies != null) this.cookies = cookies;
    if (prefix != null) this.prefix = prefix;
    if (manualHtml != null) this.manualHtml = manualHtml;
    if (isManualHtml != null) this.isManualHtml = isManualHtml;
    if (discoveredImages != null) this.discoveredImages = discoveredImages;
    if (selectedModelDbId != null) this.selectedModelDbId = selectedModelDbId;
    notifyListeners();
  }

  void addLog(String msg) {
    final stamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    logs = [...logs, '[$stamp] $msg'];
    notifyListeners();
  }

  void reset() {
    discoveredImages = [];
    logs = [];
    notifyListeners();
  }

  void notify() {
    notifyListeners();
  }
}
