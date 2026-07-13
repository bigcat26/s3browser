import 'package:flutter_test/flutter_test.dart';
import 'package:s3browser/core/config/s3_config.dart';
import 'package:s3browser/data/models/server.dart';

void main() {
  group('Server', () {
    final baseConfig = const S3Config(
      endpoint: 's3.amazonaws.com',
      region: 'us-east-1',
      accessKey: 'AKIA_TEST',
      secretKey: 'secret_test',
      defaultBucket: 'my-bucket',
      pathStyle: false,
      secure: true,
    );

    test('toJson / fromJson 往返一致', () {
      final s = Server(
        id: 'abc-123',
        name: '工作 AWS',
        config: baseConfig,
      );
      final back = Server.fromJson(s.toJson());
      expect(back.id, 'abc-123');
      expect(back.name, '工作 AWS');
      expect(back.config.endpoint, 's3.amazonaws.com');
      expect(back.config.region, 'us-east-1');
      expect(back.config.accessKey, 'AKIA_TEST');
      expect(back.config.secretKey, 'secret_test');
      expect(back.config.defaultBucket, 'my-bucket');
      expect(back.config.pathStyle, false);
      expect(back.config.secure, true);
    });

    test('copyWith 只改指定字段', () {
      final s = Server(id: 'id1', name: 'old', config: baseConfig);
      final newConfig = baseConfig.copyWith(region: 'cn-north-1');
      final s2 = s.copyWith(name: 'new', config: newConfig);
      expect(s2.id, 'id1'); // id 不变
      expect(s2.name, 'new');
      expect(s2.config.region, 'cn-north-1');
      expect(s2.config.endpoint, 's3.amazonaws.com'); // 其他 config 字段保留
    });

    test('copyWith 不传参时所有字段保持原值', () {
      final s = Server(id: 'id1', name: 'n', config: baseConfig);
      final s2 = s.copyWith();
      expect(s2.id, 'id1');
      expect(s2.name, 'n');
      expect(s2.config.endpoint, 's3.amazonaws.com');
    });

    test('toString 包含 name + endpoint', () {
      final s = Server(id: 'x', name: 'minio', config: baseConfig);
      expect(s.toString(), contains('minio'));
      expect(s.toString(), contains('s3.amazonaws.com'));
    });
  });
}
