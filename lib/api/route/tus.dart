import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core.dart';
import '../exception.dart';

/// The version of the tus protocol this client speaks.
const kTusResumableVersion = '1.0.0';

/// The most bytes [uploadFileResumably] sends in a single request.
///
/// Sending the file a chunk at a time keeps each request small enough to pass
/// through reverse proxies that cap the size of a request body.
/// A single-request upload, as in [uploadFile], has no such protection:
/// a proxy that rejects an oversized body commonly closes the connection
/// mid-upload, which reaches the client as a network error
/// rather than as the 413 the server meant to send.
const kTusChunkSizeBytes = 8 << 20; // 8 MiB

/// Upload a file with the tus resumable-upload protocol,
/// returning the uploaded file's URL for use in Markdown.
///
/// As with [uploadFile], the result is a URL relative to the realm's root.
///
/// The file is sent in chunks of at most [chunkSize],
/// reading [content] lazily, one chunk at a time.
/// [content] must produce exactly [length] bytes.
///
/// The server must support the tus endpoint: Zulip Server 10.0+,
/// i.e. feature level 296+.  On older servers, use [uploadFile].
///
/// https://tus.io/protocols/resumable-upload
Future<String> uploadFileResumably(ApiConnection connection, {
  required Stream<List<int>> content,
  required int length,
  required String filename,
  required String? contentType,
  int chunkSize = kTusChunkSizeBytes, // overridden in tests
}) async {
  final createResponse = await _createUpload(connection,
    length: length, filename: filename, contentType: contentType);

  // A zero-length upload is already complete when it's created.
  final urlFromCreate = _uploadedUrl(createResponse);
  if (urlFromCreate != null) return urlFromCreate;

  _checkStatus(createResponse, const [201]);
  final uploadUrl = _locationOf(createResponse);

  int offset = 0;
  await for (final chunk in _chunks(content, chunkSize)) {
    if (offset + chunk.length > length) {
      throw StateError('uploadFileResumably: content longer than $length bytes');
    }
    final response = await _sendChunk(connection, uploadUrl,
      chunk: chunk, offset: offset);

    final url = _uploadedUrl(response);
    if (url != null) return url;

    _checkStatus(response, const [204]);
    offset += chunk.length;
    _checkOffset(response, expected: offset);
  }

  // The server should have completed the upload once it had all the bytes.
  throw MalformedServerResponseException(
    routeName: 'uploadFileResumably', httpStatus: 204, data: null,
    causeException: StateError(
      'upload not completed after sending $offset of $length bytes'));
}

/// Create the upload, returning the server's response.
///
/// https://tus.io/protocols/resumable-upload#creation
Future<http.Response> _createUpload(ApiConnection connection, {
  required int length,
  required String filename,
  required String? contentType,
}) {
  final request = http.Request(
    'POST', connection.realmUrl.replace(path: '/api/v1/tus'));
  request.headers.addAll({
    'Tus-Resumable': kTusResumableVersion,
    'Upload-Length': length.toString(),
    'Upload-Metadata': _encodeMetadata({
      'filename': filename,
      'filetype': ?contentType,
    }),
  });
  return connection.sendRaw('uploadFileResumably', request);
}

/// Send one chunk of the file, at [offset] bytes into it.
///
/// https://tus.io/protocols/resumable-upload#patch
Future<http.Response> _sendChunk(ApiConnection connection, Uri uploadUrl, {
  required Uint8List chunk,
  required int offset,
}) {
  final request = http.Request('PATCH', uploadUrl);
  request.headers.addAll({
    'Tus-Resumable': kTusResumableVersion,
    'Upload-Offset': offset.toString(),
    'Content-Type': 'application/offset+octet-stream',
  });
  request.bodyBytes = chunk;
  return connection.sendRaw('uploadFileResumably', request);
}

/// Encode [metadata] for the `Upload-Metadata` header.
///
/// https://tus.io/protocols/resumable-upload#upload-metadata
String _encodeMetadata(Map<String, String> metadata) {
  return metadata.entries
    .map((e) => '${e.key} ${base64.encode(utf8.encode(e.value))}')
    .join(',');
}

/// The uploaded file's URL, if [response] says the upload is complete,
/// or else null.
///
/// Zulip replaces the response to whichever request completes the upload,
/// answering 200 with a JSON body that names the uploaded file
/// instead of the protocol's usual empty 204.
String? _uploadedUrl(http.Response response) {
  if (response.statusCode != 200) return null;

  final Map<String, dynamic> json;
  try {
    json = _decodeJson(response) as Map<String, dynamic>;
  } catch (e, st) {
    Error.throwWithStackTrace(MalformedServerResponseException(
      routeName: 'uploadFileResumably', httpStatus: 200, data: null,
      causeException: e), st);
  }

  final url = json['url'];
  if (url is! String) {
    throw MalformedServerResponseException(
      routeName: 'uploadFileResumably', httpStatus: 200, data: json);
  }
  return url;
}

/// The URL to send this upload's chunks to, from the response that created it.
Uri _locationOf(http.Response response) {
  final location = response.headers['location'];
  if (location == null) {
    throw MalformedServerResponseException(
      routeName: 'uploadFileResumably', httpStatus: response.statusCode,
      data: null,
      causeException: StateError('missing Location header'));
  }
  // The server may give a relative URL; resolve it the way a browser would.
  return response.request!.url.resolve(location);
}

/// Throw unless [response] reports the upload's offset as [expected].
void _checkOffset(http.Response response, {required int expected}) {
  final offset = int.tryParse(response.headers['upload-offset'] ?? '');
  if (offset != expected) {
    throw MalformedServerResponseException(
      routeName: 'uploadFileResumably', httpStatus: response.statusCode,
      data: null,
      causeException: StateError(
        'Upload-Offset was ${offset ?? 'absent'}, expected $expected'));
  }
}

/// Throw unless [response] has one of the [expected] statuses.
void _checkStatus(http.Response response, List<int> expected) {
  if (expected.contains(response.statusCode)) return;

  Map<String, dynamic>? json;
  try {
    json = _decodeJson(response) as Map<String, dynamic>?;
  } catch (e) {
    // Not a JSON object; leave `json` null, as [makeApiException] expects.
  }
  throw makeApiException('uploadFileResumably', response.statusCode, json);
}

/// Decode [response]'s body as JSON.
///
/// The body is decoded as UTF-8, like [ApiConnection.send] does.
/// Reading `response.body` instead would decode as Latin-1 whenever the
/// server doesn't name a charset, mangling any non-ASCII text.
Object? _decodeJson(http.Response response) {
  return jsonDecode(utf8.decode(response.bodyBytes));
}

/// Regroup [content] into chunks of exactly [chunkSize] bytes,
/// except the last, which may be shorter.
Stream<Uint8List> _chunks(Stream<List<int>> content, int chunkSize) async* {
  final buffer = BytesBuilder(copy: false);
  await for (final data in content) {
    buffer.add(data);
    if (buffer.length < chunkSize) continue;

    final bytes = buffer.takeBytes();
    var start = 0;
    while (bytes.length - start >= chunkSize) {
      yield Uint8List.sublistView(bytes, start, start + chunkSize);
      start += chunkSize;
    }
    if (start < bytes.length) {
      buffer.add(Uint8List.sublistView(bytes, start));
    }
  }
  if (buffer.isNotEmpty) yield buffer.takeBytes();
}
