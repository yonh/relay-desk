import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/core/platform/webview_adapter.dart';

void main() {
  test('IsolationMode dbValue roundtrips', () {
    for (final mode in IsolationMode.values) {
      expect(IsolationMode.fromDb(mode.dbValue), mode);
    }
  });

  test('IsolationMode isIsolated', () {
    expect(IsolationMode.nativeProfile.isIsolated, true);
    expect(IsolationMode.originProxy.isIsolated, true);
    expect(IsolationMode.sharedSession.isIsolated, false);
  });

  test('PanelRuntimeConfig fingerprint changes on config change', () {
    final c1 = PanelRuntimeConfig(
      identityId: 'id1',
      url: 'https://example.com',
      isolationMode: IsolationMode.nativeProfile,
    );
    final c2 = PanelRuntimeConfig(
      identityId: 'id1',
      url: 'https://example.com',
      isolationMode: IsolationMode.originProxy,
    );
    expect(c1.fingerprint, isNot(equals(c2.fingerprint)));
  });

  test('Project copyWith preserves id and createdAt', () {
    final p = Project(
      id: 'x',
      name: 'N',
      targetUrl: 'https://a.com',
      createdAt: 100,
      updatedAt: 100,
    );
    final updated = p.copyWith(name: 'N2');
    expect(updated.id, 'x');
    expect(updated.createdAt, 100);
    expect(updated.name, 'N2');
  });
}
