import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/files/directory_access_service.dart';
import 'package:joycai_image_ai_toolkits/services/files/installation_migration_service.dart';
import 'package:joycai_image_ai_toolkits/state/installation_migration_state.dart';

void main() {
  test('requires source and acknowledgement; cancellation retains selection', () async {
    final service = _Migration();
    final access = _Picker()..selected = '/old';
    final state = InstallationMigrationState(service: service, access: access);
    await state.importSelected();
    expect(service.imports, 0);
    await state.selectSource('pick');
    await state.importSelected();
    expect(service.imports, 0);
    access.selected = null;
    await state.selectSource('pick');
    expect(state.source, '/old');
    state.acknowledge(true);
    await state.importSelected();
    expect(service.imports, 1);
    expect(state.imported, isTrue);
    expect(state.destination, '/private');
    await state.importSelected();
    expect(service.imports, 1);
    state.dispose();
  });

  test('failed copy stays retryable and never claims success', () async {
    final service = _Migration()..fail = true;
    final state = InstallationMigrationState(
      service: service,
      access: _Picker()..selected = '/old',
    );
    await state.selectSource('pick');
    state.acknowledge(true);
    await state.importSelected();
    expect(state.imported, isFalse);
    expect(state.busy, isFalse);
    expect(state.error, InstallationMigrationError.sourceChanged);
    service.fail = false;
    await state.importSelected();
    expect(state.imported, isTrue);
    expect(state.error, isNull);
    state.dispose();
  });

  test('choosing a different source requires confirmation again', () async {
    final access = _Picker()..selected = '/old';
    final state = InstallationMigrationState(service: _Migration(), access: access);
    await state.selectSource('pick');
    state.acknowledge(true);
    access.selected = '/other';
    await state.selectSource('pick');
    expect(state.acknowledged, isFalse);
    state.dispose();
  });
}

class _Migration extends InstallationMigrationService {
  int imports = 0;
  bool fail = false;
  @override
  Future<String> importDirectory(String sourcePath) async {
    imports++;
    if (fail) throw const InstallationMigrationException(InstallationMigrationError.sourceChanged);
    return '/private';
  }
}

class _Picker extends DirectoryAccessService {
  String? selected;
  @override
  Future<String?> pickDirectory({
    String? initialDirectory,
    String? dialogTitle,
    bool readOnly = false,
    String? requiredPath,
  }) async => selected;
}
