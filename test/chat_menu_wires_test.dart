import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The dispatcher's chat-wire table is exhaustive and refuses a non-chat
/// wire instead of quietly sending it a ① body. That refusal stays
/// unreachable only while every vendor's chat menu lists chat wires alone.
void main() {
  const chatWires = {
    WireProtocol.openaiChat,
    WireProtocol.openaiResponses,
    WireProtocol.anthropicChat,
    WireProtocol.geminiChat,
    WireProtocol.dashscopeChat,
  };

  test('every vendor chat menu lists only chat wires', () {
    // Midjourney's family "chat" is the imagine flow, dispatched by its own
    // branch at every call site; it never reaches the chat-wire table.
    for (final vendor in Vendors.all.where((v) => v.family != ProtocolFamily.midjourney)) {
      for (final face in vendor.menuFor(Surface.chat)) {
        expect(chatWires, contains(face), reason: '${vendor.id}: ${face.id}');
      }
    }
  });
}
