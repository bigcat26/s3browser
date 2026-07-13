// S3Config 单元测试.

import 'package:s3browser/core/config/s3_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('S3Config.normalizedEndpoint', () {
    test('加 https:// 当没 scheme', () {
      final cfg = S3Config(
        endpoint: 's3.amazonaws.com',
        region: 'us-east-1',
        accessKey: 'a',
        secretKey: 'b',
        pathStyle: true,
        secure: true,
      );
      expect(cfg.normalizedEndpoint, 'https://s3.amazonaws.com');
    });

    test('http:// 明示时保持', () {
      final cfg = S3Config(
        endpoint: 'http://localhost:9000',
        region: 'us-east-1',
        accessKey: 'a',
        secretKey: 'b',
        pathStyle: true,
        secure: false,
      );
      expect(cfg.normalizedEndpoint, 'http://localhost:9000');
    });

    test('https:// 明示时保持', () {
      final cfg = S3Config(
        endpoint: 'https://minio.example.com',
        region: 'us-east-1',
        accessKey: 'a',
        secretKey: 'b',
        pathStyle: true,
        secure: true,
      );
      expect(cfg.normalizedEndpoint, 'https://minio.example.com');
    });

    test('末尾 / 自动去掉', () {
      final cfg = S3Config(
        endpoint: 'https://s3.amazonaws.com/',
        region: 'us-east-1',
        accessKey: 'a',
        secretKey: 'b',
        pathStyle: true,
        secure: true,
      );
      expect(cfg.normalizedEndpoint, 'https://s3.amazonaws.com');
    });
  });

  group('S3Config.copyWith', () {
    test('不传 = 返回相等副本', () {
      final cfg = S3Config(
        endpoint: 's3.amazonaws.com',
        region: 'us-east-1',
        accessKey: 'a',
        secretKey: 'b',
        pathStyle: true,
        secure: true,
        defaultBucket: 'my-bucket',
      );
      final c2 = cfg.copyWith();
      expect(c2.endpoint, cfg.endpoint);
      expect(c2.region, cfg.region);
      expect(c2.accessKey, cfg.accessKey);
      expect(c2.secretKey, cfg.secretKey);
      expect(c2.pathStyle, cfg.pathStyle);
      expect(c2.secure, cfg.secure);
      expect(c2.defaultBucket, cfg.defaultBucket);
    });

    test('覆盖 endpoint', () {
      final cfg = S3Config(
        endpoint: 's3.amazonaws.com',
        region: 'us-east-1',
        accessKey: 'a',
        secretKey: 'b',
        pathStyle: true,
        secure: true,
      );
      final c2 = cfg.copyWith(endpoint: 's3.us-west-2.amazonaws.com');
      expect(c2.endpoint, 's3.us-west-2.amazonaws.com');
      expect(c2.region, cfg.region);
    });
  });

  group('S3Config.toJson / fromJson (round-trip)', () {
    test('normal case 往返一致', () {
      final cfg = S3Config(
        endpoint: 'http://localhost:9000',
        region: 'us-east-1',
        accessKey: 'AKIA/+/=',
        secretKey: 'secret+with/sp ecial=chars',
        pathStyle: true,
        secure: false,
        defaultBucket: 'photos',
      );
      final restored = S3Config.fromJson(cfg.toJson());
      expect(restored.endpoint, cfg.endpoint);
      expect(restored.region, cfg.region);
      expect(restored.accessKey, cfg.accessKey);
      expect(restored.secretKey, cfg.secretKey);
      expect(restored.pathStyle, cfg.pathStyle);
      expect(restored.secure, cfg.secure);
      expect(restored.defaultBucket, cfg.defaultBucket);
    });

    test('toJson 包含 defaultBucket=null 当为空', () {
      final cfg = S3Config(
        endpoint: 's3.amazonaws.com',
        region: 'us-east-1',
        accessKey: 'a',
        secretKey: 'b',
        pathStyle: true,
        secure: true,
      );
      final j = cfg.toJson();
      expect(j['defaultBucket'], isNull);
    });
  });
}
