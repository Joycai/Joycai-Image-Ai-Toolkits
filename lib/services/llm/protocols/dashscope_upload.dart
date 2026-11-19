import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import '../channel_upload_config.dart';
import '../llm_types.dart';
import 'dashscope_files.dart';
import 'dashscope_payload.dart';
import 'protocol.dart';

/// Temporary upload supports Beijing and Singapore. Keep custom gateway bases,
/// including workspace/plan domains: credentials must stay on the configured host.
String dashscopeUploadBase(String endpoint) {
  final native = dashscopeNativeBase(endpoint);
  final uri = Uri.parse(native);
  if (uri.host.endsWith('.maas.aliyuncs.com')) {
    if (uri.host == 'cn-beijing.maas.aliyuncs.com' ||
        uri.host.endsWith('.cn-beijing.maas.aliyuncs.com')) {
      return native;
    }
    if (uri.host == 'ap-southeast-1.maas.aliyuncs.com' ||
        uri.host.endsWith('.ap-southeast-1.maas.aliyuncs.com')) {
      return native;
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

/// Resolve only the upload endpoint; never fall back to inference credentials
/// for a plan channel, even when its independent configuration is incomplete.
String dashscopeMediaUploadBase(LLMModelConfig config) {
  final upload = config.uploadConfig;
  if (upload?.tokenPlan == true || ChannelUploadConfig.isTokenPlan(config.endpoint)) {
    if (upload == null ||
        !upload.tokenPlan ||
        upload.endpoint.trim().isEmpty ||
        upload.apiKey.trim().isEmpty) {
      throw LLMApiException(
        'Token Plan requires a separate media upload endpoint and API key in channel settings. Nothing was sent.',
      );
    }
    final uri = Uri.tryParse(upload.endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        ChannelUploadConfig.isTokenPlan(upload.endpoint)) {
      throw LLMApiException(
        'Media upload requires a non-Token Plan HTTPS endpoint. Nothing was sent.',
      );
    }
    final base = dashscopeUploadBase(upload.endpoint);
    final host = Uri.parse(base).host;
    if (host == 'dashscope-intl.aliyuncs.com' ||
        host == 'ap-southeast-1.maas.aliyuncs.com' ||
        host.endsWith('.ap-southeast-1.maas.aliyuncs.com')) {
      throw LLMApiException(
        'Token Plan file management requires a Beijing upload endpoint. Nothing was sent.',
      );
    }
    return base;
  }
  return dashscopeUploadBase(config.endpoint);
}

bool dashscopeSupportsTemporaryUpload(String endpoint) {
  try {
    dashscopeUploadBase(endpoint);
    return true;
  } on LLMApiException {
    return false;
  }
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
  if (target.config.uploadConfig?.tokenPlan == true) {
    return uploadDashScopeFile(
      client: client,
      base: dashscopeMediaUploadBase(target.config),
      apiKey: target.config.uploadConfig!.apiKey.trim(),
      file: file,
      mime: mime,
      checkCancelled: checkCancelled,
      options: options,
    );
  }
  final uri = Uri.parse('${dashscopeMediaUploadBase(target.config)}/uploads')
      .replace(queryParameters: {'action': 'getPolicy', 'model': target.config.modelId});
  // This GET and the OSS upload must NOT fire the paid-submit body-sent hook.
  final request = buildJsonRequest(
    'GET',
    uri,
    headers: {
      ...target.headers(),
      if (target.config.uploadConfig?.tokenPlan == true)
        'Authorization': 'Bearer ${target.config.uploadConfig!.apiKey.trim()}',
    },
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
