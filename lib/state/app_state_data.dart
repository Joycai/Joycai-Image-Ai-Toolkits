part of 'app_state.dart';

/// Database-backed CRUD for prompts, tags, models, channels and pricing groups.
///
/// Split out of [AppState] as a `part of` extension so the core state file keeps
/// to app lifecycle and in-memory state. Notifications route through [AppState.notify]
/// because `notifyListeners` is protected to the class.
extension AppStateData on AppState {
  // Prompt Tags Methods
  Future<List<PromptTag>> getPromptTags() => _db.getPromptTags();
  Future<int> addPromptTag(Map<String, dynamic> tag) async {
    final id = await _db.addPromptTag(tag);
    notify();
    return id;
  }
  Future<void> updatePromptTag(int id, Map<String, dynamic> tag) async {
    await _db.updatePromptTag(id, tag);
    notify();
  }
  Future<void> deletePromptTag(int id) async {
    await _db.deletePromptTag(id);
    notify();
  }
  Future<void> updateTagOrder(List<int> ids) => _db.updateTagOrder(ids);

  // Prompts Methods
  Future<List<Prompt>> getPrompts() => _db.getPrompts();
  Future<int> addPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    final id = await _db.addPrompt(prompt, tagIds: tagIds);
    notify();
    return id;
  }
  Future<void> updatePrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    await _db.updatePrompt(id, prompt, tagIds: tagIds);
    notify();
  }
  Future<void> deletePrompt(int id) async {
    await _db.deletePrompt(id);
    notify();
  }
  Future<void> updatePromptOrder(List<int> ids) => _db.updatePromptOrder(ids);

  Future<void> deletePrompts(List<int> ids) async {
    await _db.deletePrompts(ids);
    notify();
  }

  Future<void> updatePromptsTags(List<int> promptIds, List<int> tagIds) async {
    await _db.updatePromptsTags(promptIds, tagIds);
    notify();
  }

  // Prompt History Methods
  Future<void> loadPromptHistory() async {
    imagePromptHistory = await _db.getPromptHistory(PromptHistoryType.image);
    videoPromptHistory = await _db.getPromptHistory(PromptHistoryType.video);
    notify();
  }

  /// Record a submitted prompt and refresh the in-memory lists so the pickers
  /// in both config panels pick it up without a reload.
  Future<void> recordPromptHistory(PromptHistoryType type, String content) async {
    await _db.addPromptHistory(type, content);
    await loadPromptHistory();
  }

  Future<void> clearPromptHistory(PromptHistoryType type) async {
    await _db.clearPromptHistory(type);
    await loadPromptHistory();
  }

  // System Prompts Methods
  Future<List<SystemPrompt>> getSystemPrompts({String? type}) => _db.getSystemPrompts(type: type);
  Future<int> addSystemPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    final id = await _db.addSystemPrompt(prompt, tagIds: tagIds);
    notify();
    return id;
  }
  Future<void> updateSystemPrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    await _db.updateSystemPrompt(id, prompt, tagIds: tagIds);
    notify();
  }
  Future<void> deleteSystemPrompt(int id) async {
    await _db.deleteSystemPrompt(id);
    notify();
  }
  Future<void> deleteSystemPrompts(List<int> ids) async {
    await _db.deleteSystemPrompts(ids);
    notify();
  }
  Future<void> updateSystemPromptsTags(List<int> promptIds, List<int> tagIds) async {
    await _db.updateSystemPromptsTags(promptIds, tagIds);
    notify();
  }
  Future<void> updateSystemPromptOrder(List<int> ids) => _db.updateSystemPromptOrder(ids);

  Future<void> importPromptData(Map<String, dynamic> data, {bool replace = false}) async {
    await _db.importPromptData(data, replace: replace);
    notify();
  }

  Future<void> restoreBackup(Map<String, dynamic> data) async {
    await _db.restoreBackup(data);
    await loadSettings();
    notify();
  }

  // Model, Channel & Pricing Group Management
  Future<void> refreshDataCache() async {
    _models = await _db.getModels();
    _channels = await _db.getChannels();
    _pricingGroups = await _db.getPricingGroups();
    notify();
  }

  Future<int> addChannel(Map<String, dynamic> channel) async {
    final id = await _db.addChannel(channel);
    await refreshDataCache();
    return id;
  }

  Future<void> updateChannel(int id, Map<String, dynamic> channel) async {
    await _db.updateChannel(id, channel);
    await refreshDataCache();
  }

  Future<void> deleteChannel(int id) async {
    await _db.deleteChannel(id);
    await refreshDataCache();
  }

  Future<int> addModel(Map<String, dynamic> model) async {
    final id = await _db.addModel(model);
    await refreshDataCache();
    return id;
  }

  Future<void> updateModel(int id, Map<String, dynamic> model) async {
    await _db.updateModel(id, model);
    await refreshDataCache();
  }

  Future<void> deleteModel(int id) async {
    await _db.deleteModel(id);
    await refreshDataCache();
  }

  Future<void> updateModelOrder(List<int> ids) async {
    await _db.updateModelOrder(ids);
    await refreshDataCache();
  }

  // Pricing Group Management
  Future<int> addPricingGroup(Map<String, dynamic> group) async {
    final id = await _db.addPricingGroup(group);
    await refreshDataCache();
    return id;
  }

  Future<void> updatePricingGroup(int id, Map<String, dynamic> group) async {
    await _db.updatePricingGroup(id, group);
    await refreshDataCache();
  }

  Future<void> deletePricingGroup(int id) async {
    await _db.deletePricingGroup(id);
    await refreshDataCache();
  }
}
