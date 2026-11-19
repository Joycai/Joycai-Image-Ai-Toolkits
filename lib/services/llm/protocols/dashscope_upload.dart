import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import '../llm_types.dart';
import 'dashscope_payload.dart';
import 'protocol.dart';

/// Temporary upload supports Beijing and Singapore. Keep custom gateway bases,
/// but never silently send an official region's credentials to another region.
String dashscopeUploadBase(String endpoint) {
  final native = dashscopeNativeBase(endpoint);
  final uri = Uri.parse(native);
  if (uri.host.endsWith('.maas.aliyuncs.com')) {
    if (uri.host == 'cn-beijing.maas.aliyuncs.com' ||
        uri.host.endsWith('.cn-beijing.maas.aliyuncs.com')) {
      return 'https://dashscope.aliyuncs.com/api/v1';
    }
    if (uri.host == 'ap-southeast-1.maas.aliyuncs.com' ||
        uri.host.endsWith('.ap-southeast-1.maas.aliyuncs.com')) {
      return 'https://dashscope-intl.aliyuncs.com/api/v1';
    }
    throw LLMApiException('Temporary media upload supports Beijing and Singapore only.');
  }
  if (uri.host.startsWith('dashscope') &&
      uri.host.endsWith('.aliyuncs.com') &&
      !['dashscope.aliyuncs.com', 'dashscope-intl.aliyuncs.com'].contains(uri.host)) {
    throw LLMApiException('Temporary media upload supports Beijing and Singapore only.');
  }
  return native;
}

/// Uploads one already validated private snapshot. URLs and policies are
/// attempt-local, never logged or persisted; retries obtain fresh credentials.
/// The caller owns the consent/proxy-aware client and its lifetime.
Future<String> uploadDashScopeMedia({
  required http.Client client,
  required LLMTarget target,
  required File file,
  required String mime,
  required void Function() checkCancelled,
  Map<String, dynamic>? options,
}) async {
  checkCancelled();
  final uri = Uri.parse('${dashscopeUploadBase(target.config.endpoint)}/uploads')
      .replace(queryParameters: {'action': 'getPolicy', 'model': target.config.modelId});
  // This GET and the OSS upload must NOT fire the paid-submit body-sent hook.
  final request = buildJsonRequest(
    'GET',
    uri,
    headers: target.headers(),
    body: '',
    options: options,
  );
  final response = await http.Response.fromStream(await client.send(request));
  checkCancelled();
  if (response.statusCode != 200) {
    throw LLMApiException('DashScope upload policy failed (HTTP ${response.statusCode}).');
  }
  final Map<String, dynamic> policy;
  try {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    policy = (decoded['data'] as Map).cast<String, dynamic>();
  } catch (_) {
    throw LLMApiException('DashScope returned an invalid upload policy.');
  }
  String requiredField(String key) {
    final value = policy[key];
    if (value is! String || value.isEmpty) {
      throw LLMApiException('DashScope upload policy is missing $key.');
    }
    return value;
  }

  final host = Uri.tryParse(requiredField('upload_host'));
  if (host == null ||
      host.scheme != 'https' ||
      host.host.isEmpty ||
      host.userInfo.isNotEmpty ||
      host.hasFragment) {
    throw LLMApiException('DashScope upload policy requires a valid HTTPS destination.');
  }
  final directory = requiredField('upload_dir');
  if (!directory.startsWith('dashscope-instant/') ||
      directory.split('/').any((s) => s == '..') ||
      directory.contains('?') ||
      directory.contains('#') ||
      directory.contains('\\')) {
    throw LLMApiException('DashScope returned an invalid upload directory.');
  }
  final extension = switch (mime) {
    'video/mp4' => 'mp4',
    'video/quicktime' => 'mov',
    'audio/wav' => 'wav',
    'audio/mpeg' => 'mp3',
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/bmp' => 'bmp',
    'image/webp' => 'webp',
    _ => throw LLMApiException('Unsupported upload media format.'),
  };
  final name = '${const Uuid().v4()}.$extension';
  final key = '${directory.replaceFirst(RegExp(r'/+$'), '')}/$name';
  final upload = http.AbortableMultipartRequest('POST', host, abortTrigger: abortTriggerOf(options))
    ..followRedirects = false
    ..fields.addAll({
      'OSSAccessKeyId': requiredField('oss_access_key_id'),
      'Signature': requiredField('signature'),
      'policy': requiredField('policy'),
      'x-oss-object-acl': requiredField('x_oss_object_acl'),
      'x-oss-forbid-overwrite': requiredField('x_oss_forbid_overwrite'),
      'key': key,
      'success_action_status': '200',
    })
    ..files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: name,
        contentType: MediaType.parse(mime),
      ),
    );
  // No API Authorization header on the signed storage destination. Multipart
  // serializes fields first and the file last, as OSS requires.
  checkCancelled();
  final uploaded = await http.Response.fromStream(await client.send(upload));
  checkCancelled();
  if (uploaded.statusCode != 200) {
    throw LLMApiException('DashScope media upload failed (HTTP ${uploaded.statusCode}).');
  }
  return 'oss://$key';
}
