import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:http/http.dart' as http;
import 'package:test/scaffolding.dart';
import 'package:zulip/api/exception.dart';
import 'package:zulip/api/route/tus.dart';

import '../../stdlib_checks.dart';
import '../exception_checks.dart';
import '../fake_api.dart';

/// The path the server hands out for sending an upload's chunks.
const uploadPath = '/api/v1/tus/PJhRqwcMDCZ6pg7zQGKqhw';

/// The URL of the finished file, as the server reports it on completion.
const resultUrl = '/user_uploads/1/4e/m2A3MSqFnWRLUf9SaPzQ0Up_/file.txt';

/// Prepare the response that creates an upload.
void prepareCreated(FakeApiConnection connection, {String? location}) {
  connection.prepare(httpStatus: 201, headers: {
    'tus-resumable': '1.0.0',
    'location': location ?? uploadPath,
  });
}

/// Prepare the response to a chunk that doesn't finish the upload.
void prepareChunkAccepted(FakeApiConnection connection, {required int offset}) {
  connection.prepare(httpStatus: 204, headers: {
    'tus-resumable': '1.0.0',
    'upload-offset': offset.toString(),
  });
}

/// Prepare the response to the request that completes the upload.
void prepareCompleted(FakeApiConnection connection) {
  connection.prepare(httpStatus: 200,
    json: {'url': resultUrl, 'filename': 'file.txt'});
}

String base64Utf8(String value) => base64.encode(utf8.encode(value));

Future<String> uploadAsdf(FakeApiConnection connection, {int? chunkSize}) {
  return uploadFileResumably(connection,
    content: Stream.fromIterable(['asdf'.codeUnits]),
    length: 4,
    filename: 'file.txt',
    contentType: 'text/plain',
    chunkSize: chunkSize ?? kTusChunkSizeBytes);
}

void main() {
  group('uploadFileResumably', () {
    test('smoke', () {
      return FakeApiConnection.with_((connection) async {
        prepareCreated(connection);
        prepareCompleted(connection);
        check(await uploadAsdf(connection)).equals(resultUrl);

        final requests = connection.takeRequests();
        check(requests).length.equals(2);

        final create = requests[0] as http.Request;
        check(create)
          ..method.equals('POST')
          ..url.path.equals('/api/v1/tus');
        check(create.headers['tus-resumable']).equals('1.0.0');
        check(create.headers['upload-length']).equals('4');
        check(create.headers['upload-metadata']).equals(
          'filename ${base64Utf8('file.txt')}'
          ',filetype ${base64Utf8('text/plain')}');

        final chunk = requests[1] as http.Request;
        check(chunk)
          ..method.equals('PATCH')
          ..url.path.equals(uploadPath)
          ..bodyBytes.deepEquals('asdf'.codeUnits);
        check(chunk.headers['tus-resumable']).equals('1.0.0');
        check(chunk.headers['upload-offset']).equals('0');
        check(chunk.headers['content-type'])
          .equals('application/offset+octet-stream');
      });
    });

    test('no mime type', () {
      return FakeApiConnection.with_((connection) async {
        prepareCreated(connection);
        prepareCompleted(connection);
        await uploadFileResumably(connection,
          content: Stream.fromIterable(['asdf'.codeUnits]),
          length: 4,
          filename: 'file.txt',
          contentType: null);
        check(connection.takeRequests()[0].headers['upload-metadata'])
          .equals('filename ${base64Utf8('file.txt')}');
      });
    });

    test('non-ASCII result URL', () {
      // The server doesn't name a charset, so the body must be read as UTF-8
      // explicitly; reading it as Latin-1 would mangle the filename.
      const url = '/user_uploads/1/4e/m2A3MSqFnWRLUf9SaPzQ0Up_/한국어 파일.txt';
      return FakeApiConnection.with_((connection) async {
        prepareCreated(connection);
        connection.prepare(httpStatus: 200,
          json: {'url': url, 'filename': '한국어 파일.txt'});
        check(await uploadAsdf(connection)).equals(url);
      });
    });

    test('absolute Location', () {
      return FakeApiConnection.with_((connection) async {
        prepareCreated(connection,
          location: 'https://chat.example$uploadPath');
        prepareCompleted(connection);
        check(await uploadAsdf(connection)).equals(resultUrl);
        check(connection.takeRequests()[1]).url
          .equals(Uri.parse('https://chat.example$uploadPath'));
      });
    });

    test('send in chunks', () {
      return FakeApiConnection.with_((connection) async {
        prepareCreated(connection);
        prepareChunkAccepted(connection, offset: 4);
        prepareChunkAccepted(connection, offset: 8);
        prepareCompleted(connection);
        // The content arrives in pieces that don't line up with the chunks.
        final result = await uploadFileResumably(connection,
          content: Stream.fromIterable(
            ['abcde'.codeUnits, 'fg'.codeUnits, 'hij'.codeUnits]),
          length: 10,
          filename: 'file.txt',
          contentType: 'text/plain',
          chunkSize: 4);
        check(result).equals(resultUrl);

        final chunks = connection.takeRequests().skip(1)
          .map((r) => r as http.Request).toList();
        check(chunks).length.equals(3);
        check(chunks[0].headers['upload-offset']).equals('0');
        check(chunks[0]).bodyBytes.deepEquals('abcd'.codeUnits);
        check(chunks[1].headers['upload-offset']).equals('4');
        check(chunks[1]).bodyBytes.deepEquals('efgh'.codeUnits);
        check(chunks[2].headers['upload-offset']).equals('8');
        check(chunks[2]).bodyBytes.deepEquals('ij'.codeUnits);
      });
    });

    test('zero-length file completes on creation', () {
      return FakeApiConnection.with_((connection) async {
        prepareCompleted(connection);
        final result = await uploadFileResumably(connection,
          content: Stream<List<int>>.empty(),
          length: 0,
          filename: 'file.txt',
          contentType: 'text/plain');
        check(result).equals(resultUrl);
        check(connection.takeRequests()).single.method.equals('POST');
      });
    });

    test('server rejects the upload', () {
      return FakeApiConnection.with_((connection) async {
        connection.prepare(httpStatus: 413, json: {
          'result': 'error',
          'code': 'BAD_REQUEST',
          'msg': 'File is larger than the maximum upload size (80 MiB).',
        });
        await check(uploadAsdf(connection)).throws<ZulipApiException>((it) => it
          ..httpStatus.equals(413)
          ..message.equals(
            'File is larger than the maximum upload size (80 MiB).'));
      });
    });

    test('no Location on the created upload', () {
      return FakeApiConnection.with_((connection) async {
        connection.prepare(httpStatus: 201, headers: {'tus-resumable': '1.0.0'});
        await check(uploadAsdf(connection))
          .throws<MalformedServerResponseException>();
      });
    });

    test('server reports an unexpected offset', () {
      return FakeApiConnection.with_((connection) async {
        prepareCreated(connection);
        prepareChunkAccepted(connection, offset: 3); // should be 4
        await check(uploadAsdf(connection, chunkSize: 4))
          .throws<MalformedServerResponseException>();
      });
    });

    test('no completion after the last chunk', () {
      return FakeApiConnection.with_((connection) async {
        prepareCreated(connection);
        prepareChunkAccepted(connection, offset: 4);
        await check(uploadAsdf(connection, chunkSize: 4))
          .throws<MalformedServerResponseException>();
      });
    });
  });
}
