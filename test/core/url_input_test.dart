import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/core/url_input.dart';

void main() {
  group('normalizeUrlInput', () {
    test('adds https to bare public domains', () {
      expect(normalizeUrlInput('example.com'), 'https://example.com');
      expect(normalizeUrlInput('www.baidu.com'), 'https://www.baidu.com');
      expect(
        normalizeUrlInput('  github.com/yonh/relay-desk?tab=1#x '),
        'https://github.com/yonh/relay-desk?tab=1#x',
      );
      expect(normalizeUrlInput('example.com:8443'), 'https://example.com:8443');
      expect(normalizeUrlInput('8.8.8.8'), 'https://8.8.8.8');
      expect(normalizeUrlInput('//example.com/a'), 'https://example.com/a');
    });

    test('adds http to local and private hosts', () {
      expect(normalizeUrlInput('localhost'), 'http://localhost');
      expect(
        normalizeUrlInput('localhost:3000/app'),
        'http://localhost:3000/app',
      );
      expect(normalizeUrlInput('127.0.0.1:8080'), 'http://127.0.0.1:8080');
      expect(normalizeUrlInput('192.168.1.5'), 'http://192.168.1.5');
      expect(normalizeUrlInput('10.0.0.2:5173'), 'http://10.0.0.2:5173');
      expect(normalizeUrlInput('172.20.1.1'), 'http://172.20.1.1');
      expect(normalizeUrlInput('printer.local'), 'http://printer.local');
      expect(normalizeUrlInput('[::1]:3000'), 'http://[::1]:3000');
    });

    test('keeps inputs that already have a scheme', () {
      expect(normalizeUrlInput('https://example.com'), 'https://example.com');
      expect(normalizeUrlInput('http://example.com/x'), 'http://example.com/x');
      expect(normalizeUrlInput('HTTPS://Example.com'), 'HTTPS://Example.com');
      expect(normalizeUrlInput('file:///tmp/a.html'), 'file:///tmp/a.html');
      expect(normalizeUrlInput('about:blank'), 'about:blank');
    });

    test('rejects input that is not a URL', () {
      expect(normalizeUrlInput(''), isNull);
      expect(normalizeUrlInput('   '), isNull);
      expect(normalizeUrlInput('hello world'), isNull);
      expect(normalizeUrlInput('justaword'), isNull);
    });
  });
}
