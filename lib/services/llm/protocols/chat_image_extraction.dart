import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../core/image_magic.dart';

/// Images carried by a structured (non-text) response field.
///
/// Relays disagree on how a generated image comes back. New API's own Gemini
/// adapter writes markdown `![image](data:…)` into `content`, which the text
/// scan handles; others use `images: [{image_url: {url}}]` or a bare
/// `image_data` base64 string. [urls] holds `http(s)` entries the caller must
/// still fetch — a relay backed by object storage returns a link rather than
/// the bytes, and dropping those was indistinguishable from generating nothing.
class StructuredImages {
  final List<Uint8List> bytes;
  final List<String> urls;
  const StructuredImages(this.bytes, this.urls);

  bool get isEmpty => bytes.isEmpty && urls.isEmpty;
}

/// Reads the structured image fields of a `message` (sync) or `delta`
/// (streaming) object. Unknown shapes contribute nothing.
StructuredImages extractStructuredImages(Map<String, dynamic> source) {
  final bytes = <Uint8List>[];
  final urls = <String>[];

  void addUrl(String url) {
    if (url.startsWith('data:image/')) {
      final comma = url.indexOf(',');
      if (comma == -1) return;
      try {
        bytes.add(base64Decode(url.substring(comma + 1)));
      } catch (_) {
        /* not decodable — nothing to add */
      }
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      urls.add(url);
    }
  }

  void addBase64(Object? raw) {
    if (raw is! String || raw.isEmpty) return;
    try {
      bytes.add(base64Decode(raw));
    } catch (_) {
      /* not decodable — nothing to add */
    }
  }

  /// A bare string entry: a link, a data URI, or the base64 itself. Bare
  /// base64 is admitted only when its bytes are an image — an unlabelled
  /// string in this list has no other proof of what it is, and any short
  /// word decodes "successfully" as base64.
  void addLoose(String value) {
    if (value.startsWith('data:') || value.startsWith('http')) {
      addUrl(value);
      return;
    }
    try {
      final decoded = base64Decode(value);
      if (imageMimeFromBytes(decoded) != null) bytes.add(decoded);
    } catch (_) {
      /* not base64 — nothing to add */
    }
  }

  addBase64(source['image_data']);
  // `message.image_b64_json` — seen on a relay's gpt-image-2-via-chat, which
  // put the same picture here, in `images[0].b64_json` and in `content` at
  // once (the caller de-duplicates; see [ImageDeduper]).
  addBase64(source['image_b64_json']);

  // `images: [{ image_url: { url: "data:…"|"http…" } } | { b64_json } | { url } | "…"]`
  final imageList = source['images'];
  if (imageList is List) {
    for (final entry in imageList) {
      if (entry is String) {
        addLoose(entry);
        continue;
      }
      if (entry is! Map) continue;
      final urlField = entry['image_url'] is Map
          ? entry['image_url']['url']
          : (entry['image_url'] ?? entry['url']);
      if (urlField is String && urlField.isNotEmpty) addUrl(urlField);
      addBase64(entry['b64_json']);
    }
  }

  return StructuredImages(bytes, urls);
}

/// A reply whose *entire* text is one image: a bare link, or the bare base64
/// of the picture with no `data:` prefix and no markdown around it.
///
/// Both shapes came from the same relay serving gpt-image-2 through
/// `/chat/completions`, an hour apart — the reply shape follows whichever
/// upstream channel the relay picked. The old parser saw text with no image
/// in it, reported "the model only answered in words" and quoted the first
/// 200 characters of base64 as the model's words.
class WholeContentImage {
  /// An `http(s)` link the caller still has to fetch.
  final String? url;

  /// Decoded picture bytes.
  final Uint8List? bytes;

  const WholeContentImage._({this.url, this.bytes});
}

/// The one image [text] *is*, or null when it is prose (or a caption with an
/// embedded image, which the markdown/data-URI scans handle).
///
/// Two gates keep short prose out:
///  * a link only counts when it is the whole reply, and only when
///    [imageReply] says the model is an image generator — a chat model that
///    answers with a URL is citing, not delivering, and must not make the app
///    download it;
///  * a base64 candidate has to be at least 64 characters of the base64
///    alphabet **and decode to bytes whose magic names an image format**. The
///    alphabet alone is not enough: a one-word English answer is in it too.
WholeContentImage? wholeContentImage(String text, {required bool imageReply}) {
  final s = text.trim();
  if (s.isEmpty) return null;

  if (imageReply && RegExp(r'^https?://\S+$').hasMatch(s)) {
    return WholeContentImage._(url: s);
  }

  // Relays wrap long base64 in newlines; the alphabet test runs on the
  // joined string.
  final compact = s.replaceAll(RegExp(r'\s+'), '');
  if (compact.length < 64 || !RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(compact)) {
    return null;
  }
  Uint8List decoded;
  try {
    decoded = base64Decode(compact);
  } catch (_) {
    return null;
  }
  if (imageMimeFromBytes(decoded) == null) return null;
  return WholeContentImage._(bytes: decoded);
}

/// Keeps one copy of each distinct picture across every place a reply can
/// carry it.
///
/// A relay has been seen returning the same image three times in one reply —
/// as bare base64 in `content`, in `images[0].b64_json` and in
/// `image_b64_json` — and each copy became a file. Identity is the SHA-256 of
/// the bytes, so two copies match whatever field they came from and whatever
/// encoding they arrived in.
class ImageDeduper {
  final Set<String> _seen = {};

  /// True when [image] is new; false when an identical picture was already
  /// admitted.
  bool admit(Uint8List image) => _seen.add(sha256.convert(image).toString());

  /// [images] without the ones already admitted (or repeated within).
  List<Uint8List> filter(Iterable<Uint8List> images) => [
    for (final img in images)
      if (admit(img)) img,
  ];
}

/// Image URLs a reply's *text* points at, in declaration order, deduplicated.
///
/// Two forms count as "this is the image you asked for":
///  * a markdown image link — `![image](https://…)`. New API's Gemini adapter
///    writes exactly this shape with a `data:` URI, and relays backed by
///    object storage write it with an `http(s)` link instead; the second kind
///    used to be dropped, so those relays produced a caption and no picture.
///  * a bare `storage.googleapis.com` link, the historical Gemini case.
///
/// A bare link to any other host is deliberately *not* fetched: a chat reply
/// that merely cites a URL must not cause the app to go download it.
List<String> imageUrlsInText(String text) {
  final urls = <String>{};
  for (final m in RegExp(r'!\[[^\]]*\]\((https?://[^\s)]+)\)').allMatches(text)) {
    urls.add(m.group(1)!);
  }
  for (final m in RegExp(r'https?://storage\.googleapis\.com/[^\s"\]\)]+').allMatches(text)) {
    urls.add(m.group(0)!);
  }
  return urls.toList();
}
