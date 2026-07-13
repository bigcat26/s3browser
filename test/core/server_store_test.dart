import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:s3browser/core/config/s3_config.dart';
import 'package:s3browser/core/config/server_store.dart';
import 'package:s3browser/data/models/server.dart';

void main() {
  // 每个 test 用 setUp 初始化一份空的 SharedPreferences
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('ServerStore.load', () {
    test('空数据 → 返回空列表', () async {
      final store = ServerStore();
      final list = await store.load();
      expect(list, isEmpty);
    });

    test('空数据时不创建 legacy 假数据', () async {
      final store = ServerStore();
      await store.load();
      final p = await SharedPreferences.getInstance();
      expect(p.getString('s3browser.servers.v2'), isNull);
    });

    test('损坏的 v2 数据 → 清掉, 返回空列表', () async {
      SharedPreferences.setMockInitialValues({
        's3browser.servers.v2': 'this is not json{{{',
      });
      final store = ServerStore();
      final list = await store.load();
      expect(list, isEmpty);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('s3browser.servers.v2'), isNull);
    });
  });

  group('ServerStore.save / load 往返', () {
    test('单 server 保存后能读回', () async {
      final store = ServerStore();
      final s = Server(
        id: 'uuid-1',
        name: '工作 AWS',
        config: const S3Config(
          endpoint: 's3.amazonaws.com',
          region: 'us-east-1',
          accessKey: 'AKIA_X',
          secretKey: 'secret',
          pathStyle: false,
          secure: true,
        ),
      );
      await store.save([s]);
      final loaded = await store.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'uuid-1');
      expect(loaded.first.name, '工作 AWS');
      expect(loaded.first.config.endpoint, 's3.amazonaws.com');
      expect(loaded.first.config.accessKey, 'AKIA_X');
    });

    test('多 server 顺序保持', () async {
      final store = ServerStore();
      final servers = [
        Server(id: '1', name: 'A', config: const S3Config(
          endpoint: 'a.com', region: 'us-east-1',
          accessKey: 'a', secretKey: 'a',
        )),
        Server(id: '2', name: 'B', config: const S3Config(
          endpoint: 'b.com', region: 'us-east-1',
          accessKey: 'b', secretKey: 'b',
        )),
        Server(id: '3', name: 'C', config: const S3Config(
          endpoint: 'c.com', region: 'us-east-1',
          accessKey: 'c', secretKey: 'c',
        )),
      ];
      await store.save(servers);
      final loaded = await store.load();
      expect(loaded.map((s) => s.id).toList(), ['1', '2', '3']);
    });
  });

  group('ServerStore 旧 v1 迁移', () {
    test('v1 存在 → 包装为 Server 并删除 v1', () async {
      // 模拟旧版存的 query-string 格式
      const legacy =
          'endpoint=s3.amazonaws.com&region=us-east-1&accessKey=AKIA_LEGACY&'
          'secretKey=old_secret&defaultBucket=old-bucket&pathStyle=true&secure=true';
      SharedPreferences.setMockInitialValues({
        's3browser.config.v1': legacy,
      });

      final store = ServerStore();
      final list = await store.load();

      expect(list, hasLength(1));
      final s = list.first;
      expect(s.name, 's3.amazonaws.com'); // 默认名 = host
      expect(s.config.endpoint, 's3.amazonaws.com');
      expect(s.config.accessKey, 'AKIA_LEGACY');
      expect(s.config.defaultBucket, 'old-bucket');
      expect(s.id, isNotEmpty); // uuid 已生成

      // v1 key 已被清掉, v2 写入
      final p = await SharedPreferences.getInstance();
      expect(p.getString('s3browser.config.v1'), isNull);
      expect(p.getString('s3browser.servers.v2'), isNotNull);
    });

    test('v1 损坏 → 清掉, 返回空列表 (不抛错)', () async {
      SharedPreferences.setMockInitialValues({
        's3browser.config.v1': 'garbage_data_no_equals',
      });
      final store = ServerStore();
      final list = await store.load();
      expect(list, isEmpty);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('s3browser.config.v1'), isNull);
    });

    test('v2 已存在时不触发 v1 迁移', () async {
      // 两个 key 都存在, 应当优先用 v2
      SharedPreferences.setMockInitialValues({
        's3browser.servers.v2':
            '[{"id":"v2-id","name":"v2-name","config":{"endpoint":"v2.com","region":"us-east-1","accessKey":"v2","secretKey":"v2"}}]',
        's3browser.config.v1':
            'endpoint=legacy.com&region=us-east-1&accessKey=LEG&secretKey=LEG',
      });
      final store = ServerStore();
      final list = await store.load();
      expect(list, hasLength(1));
      expect(list.first.id, 'v2-id');
      // v1 仍然存在 (没被迁移清掉, 因为根本没进迁移分支)
      final p = await SharedPreferences.getInstance();
      expect(p.getString('s3browser.config.v1'), isNotNull);
    });
  });

  group('ServerStore.defaultName', () {
    test('无 scheme host 直接返回', () {
      final store = ServerStore();
      final cfg = const S3Config(
        endpoint: 'minio.local:9000', region: 'us-east-1',
        accessKey: 'a', secretKey: 'b',
      );
      expect(store.defaultName(cfg), 'minio.local:9000');
    });

    test('带 https:// 的 endpoint 提取 host', () {
      final store = ServerStore();
      final cfg = const S3Config(
        endpoint: 'https://s3.amazonaws.com', region: 'us-east-1',
        accessKey: 'a', secretKey: 'b',
      );
      expect(store.defaultName(cfg), 's3.amazonaws.com');
    });

    test('endpoint 为空时返回 "未命名"', () {
      final store = ServerStore();
      final cfg = const S3Config(
        endpoint: '', region: 'us-east-1',
        accessKey: 'a', secretKey: 'b',
      );
      expect(store.defaultName(cfg), '未命名');
    });
  });

  group('ServerStore.newId', () {
    test('生成 uuid 格式 (8-4-4-4-12)', () {
      final store = ServerStore();
      final id = store.newId();
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));
    });

    test('两次生成 id 不同', () {
      final store = ServerStore();
      expect(store.newId(), isNot(equals(store.newId())));
    });
  });
}
