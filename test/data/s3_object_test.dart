// S3Object 单元测试.

import 'package:s3browser/data/models/s3_object.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('S3Object.sizeHuman', () {
    S3Object fileOf(int bytes) => S3Object(
          key: 'k',
          name: 'k',
          size: bytes,
          lastModified: null,
          etag: null,
          isFolder: false,
          prefix: '',
        );

    test('0 字节 → —', () {
      expect(fileOf(0).sizeHuman, '—');
    });

    test('< 1024 → B', () {
      expect(fileOf(512).sizeHuman, '512 B');
    });

    test('KB 档 (1024 - 1MB)', () {
      expect(fileOf(1024).sizeHuman, '1.0 KB');
      expect(fileOf(1536).sizeHuman, '1.5 KB');
      expect(fileOf(1024 * 1024 - 1).sizeHuman, '1024.0 KB');
    });

    test('MB 档 (1MB - 1GB)', () {
      expect(fileOf(1024 * 1024).sizeHuman, '1.0 MB');
      expect(fileOf(1024 * 1024 * 100).sizeHuman, '100.0 MB');
    });

    test('GB 档 (>= 1GB)', () {
      expect(fileOf(1024 * 1024 * 1024).sizeHuman, '1.00 GB');
      expect(fileOf(1024 * 1024 * 1024 * 2).sizeHuman, '2.00 GB');
      expect(fileOf(int.parse('2147483648')).sizeHuman, '2.00 GB');
    });

    test('文件夹永远 —', () {
      const folder = S3Object(
        key: 'photos/',
        name: 'photos',
        size: 0,
        lastModified: null,
        etag: null,
        isFolder: true,
        prefix: '',
      );
      expect(folder.sizeHuman, '—');
    });
  });
}
