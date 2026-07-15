// S3 错误响应嗅探测试.
//
// 背景: RustFS / 部分 MinIO fork 在凭证错 / 无权限 / 路径不存在时,
// 返回 HTTP 200 + `<Error><Code>...</Code><Message>...</Message></Error>`,
// dio 默认 validateStatus 不抛, 业务代码如果不主动 sniff 就当成功.
//
// 之前 sniff 只接在 listBuckets / listObjects / deleteObjects / _createMultipartUpload
// 这几条 read/delete 链上, PUT (uploadBytes / _putObject) 走另一条, 写操作
// 失败被静默吞掉. 用户看到 "创建成功" snackbar 但服务端没建出来.
//
// 这次修法是把 sniff 抽成 [checkS3ErrorBody] + 接到 [S3Client] 的 _signedRequest
// 里. 写操作 (PUT/POST/DELETE) 也过 sniff. 防止回归.

import 'package:s3browser/data/s3_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkS3ErrorBody', () {
    test('命中 <Error> 根节点 → 抛 S3Error 带 Code + Message', () {
      const body = '''<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>NoSuchKey</Code>
  <Message>The specified key does not exist.</Message>
  <Resource>/my-bucket/missing.txt</Resource>
  <RequestId>4442587FB7D0A2F9</RequestId>
</Error>''';
      expect(
        () => checkS3ErrorBody(body),
        throwsA(
          isA<S3Error>()
              .having((e) => e.code, 'code', 'NoSuchKey')
              .having((e) => e.message, 'message',
                  'The specified key does not exist.'),
        ),
      );
    });

    test('RustFS 风格的 200 + InvalidRequest body 也要抛', () {
      // 这就是用户在某 S3 兼容服务上创建 yolo-hands/ 时服务端
      // 实际返回的 body 形态. 修前被静默吞, 修后立即抛.
      const body = '''<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>InvalidRequest</Code>
  <Message>Folder marker creation failed: parent prefix not found</Message>
</Error>''';
      expect(
        () => checkS3ErrorBody(body),
        throwsA(isA<S3Error>()
            .having((e) => e.code, 'code', 'InvalidRequest')),
      );
    });

    test('正常 ListBuckets XML body → 不抛', () {
      const body = '''<?xml version="1.0" encoding="UTF-8"?>
<ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Owner>
    <ID>owner-id</ID>
    <DisplayName>owner</DisplayName>
  </Owner>
  <Buckets>
    <Bucket><Name>my-bucket</Name></Bucket>
  </Buckets>
</ListAllMyBucketsResult>''';
      expect(() => checkS3ErrorBody(body), returnsNormally);
    });

    test('ListObjectsV2 正常响应 → 不抛', () {
      const body = '''<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <Name>my-bucket</Name>
  <Prefix>photos/</Prefix>
  <IsTruncated>false</IsTruncated>
  <Contents>
    <Key>photos/a.jpg</Key>
    <Size>1024</Size>
  </Contents>
</ListBucketResult>''';
      expect(() => checkS3ErrorBody(body), returnsNormally);
    });

    test('空 body (成功 PUT 204) → 不抛', () {
      expect(() => checkS3ErrorBody(''), returnsNormally);
    });

    test('JSON body (e.g. AWS S3 vhost 模式可能返回) → 不抛', () {
      // 不以 <?xml 或 < 开头, 不走 parse, 直接放行.
      const body = '{"ok": true}';
      expect(() => checkS3ErrorBody(body), returnsNormally);
    });

    test('纯文本错误 body (e.g. nginx 502) → 不抛', () {
      // sniff 只能处理标准 S3 XML Error 形态, 别的让上层 status code 兜底.
      const body = '502 Bad Gateway';
      expect(() => checkS3ErrorBody(body), returnsNormally);
    });

    test('body 里出现 <Error> 字符串但根不是 Error → 不抛', () {
      // 防御性: 上传文件内容里出现 "<Error>" 文本, 不应该误判.
      // 我们的 sniff 看的是 rootElement, 不是 substring.
      const body = '''<?xml version="1.0" encoding="UTF-8"?>
<CompleteMultipartUploadResult>
  <Error>some text mentioning Error</Error>
  <Bucket>my-bucket</Bucket>
</CompleteMultipartUploadResult>''';
      // 这个 root 是 CompleteMultipartUploadResult 不是 Error, 放行.
      expect(() => checkS3ErrorBody(body), returnsNormally);
    });

    test('含 <Error> 但不是 XML (e.g. HTML 错误页) → 不抛 (避免误伤)', () {
      const body = '''<html>
<body><h1>Error 403</h1><p>Access Denied</p></body>
</html>''';
      // body 含 "<Error>" 子串? 实际不包含, 但即使包含, head 不以 <?xml 开头
      // 也不会走 parse. 这里是边界: 即便真的有 "<Error>" 嵌在 HTML 里,
      // 我们也不去 parse HTML, 留给上层 status code 检查.
      expect(() => checkS3ErrorBody(body), returnsNormally);
    });

    test('body 是 "<Error>" 开头的非 XML 垃圾 → 抛 MalformedError', () {
      // 真的命中 <Error> 关键字, head 以 < 开头, 走 parse, parse 失败 →
      // catch 兜底抛 MalformedError (不要静默吞).
      const body = '<Error>truncated garbage';
      expect(
        () => checkS3ErrorBody(body),
        throwsA(isA<S3Error>()
            .having((e) => e.code, 'code', 'MalformedError')),
      );
    });
  });

  group('parseS3Xml', () {
    test('正常 body → 返回解析后的 XmlDocument', () {
      const body = '''<?xml version="1.0" encoding="UTF-8"?>
<ListAllMyBucketsResult>
  <Buckets>
    <Bucket><Name>b1</Name></Bucket>
    <Bucket><Name>b2</Name></Bucket>
  </Buckets>
</ListAllMyBucketsResult>''';
      final doc = parseS3Xml(body);
      // 根节点是 ListAllMyBucketsResult 说明 sniff 通过且 parse 成功.
      expect(doc.rootElement.name.local, 'ListAllMyBucketsResult');
    });

    test('Error body → 抛 S3Error (不返回空 doc)', () {
      const body = '<?xml version="1.0"?><Error><Code>AccessDenied</Code>'
          '<Message>Access Denied</Message></Error>';
      expect(
        () => parseS3Xml(body),
        throwsA(isA<S3Error>()
            .having((e) => e.code, 'code', 'AccessDenied')),
      );
    });
  });

  group('S3Error', () {
    test('toString 格式: "S3 <code>: <message>"', () {
      final e = S3Error('NoSuchKey', 'Key not found');
      expect(e.toString(), 'S3 NoSuchKey: Key not found');
    });

    test('is Exception (可以被 try/catch 接住)', () {
      final e = S3Error('Test', 'msg');
      expect(e, isA<Exception>());
    });
  });
}
