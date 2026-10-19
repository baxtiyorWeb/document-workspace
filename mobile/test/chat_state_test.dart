import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/models/attached_file.dart';
import 'package:mobile/features/chat/models/chat_message.dart';
import 'package:mobile/features/chat/models/chat_state.dart';

void main() {
  group('ChatMessage Model Tests', () {
    test('ChatMessage json deserialization and helper getters', () {
      final json = {
        'id': 'msg-1',
        'conversation_id': 'conv-1',
        'role': 'user',
        'content': 'Salom AI',
        'status': 'completed',
        'attached_file_ids': ['file-1', 'file-2'],
        'citations': ['1-sahifa: Kirish', '2-sahifa: Xulosa'],
        'created_at': '2026-10-14T12:00:00Z',
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.id, 'msg-1');
      expect(msg.conversationId, 'conv-1');
      expect(msg.role, 'user');
      expect(msg.content, 'Salom AI');
      expect(msg.isUser, isTrue);
      expect(msg.isAssistant, isFalse);
      expect(msg.isStreaming, isFalse);
      expect(msg.isCancelled, isFalse);
      expect(msg.isFailed, isFalse);
      expect(msg.hasFiles, isTrue);
      expect(msg.fileIds.length, 2);
      expect(msg.hasCitations, isTrue);
      expect(msg.citations.length, 2);
      expect(msg.citations.first, '1-sahifa: Kirish');
    });

    test('ChatMessage copyWith updates content, status and citations', () {
      final msg = ChatMessage(
        id: 'msg-2',
        conversationId: 'conv-1',
        role: 'assistant',
        content: 'Boshlang\'ich',
        status: 'streaming',
        createdAt: DateTime.now(),
      );

      expect(msg.isStreaming, isTrue);

      final updated = msg.copyWith(
        content: 'Yakunlangan javob',
        status: 'completed',
        citations: ['Shartnoma.pdf (1-sahifa)'],
      );

      expect(updated.id, 'msg-2');
      expect(updated.content, 'Yakunlangan javob');
      expect(updated.status, 'completed');
      expect(updated.isStreaming, isFalse);
      expect(updated.hasCitations, isTrue);
      expect(updated.citations.first, 'Shartnoma.pdf (1-sahifa)');
    });
  });

  group('AttachedFile Model Tests', () {
    test('AttachedFile format size and type identification', () {
      const pdf = AttachedFile(
        id: 'file-pdf-1',
        name: 'hisobot.pdf',
        sizeBytes: 1024 * 1024 * 2, // 2MB
        mimeType: 'application/pdf',
      );
      expect(pdf.isPdf, isTrue);
      expect(pdf.isImage, isFalse);
      expect(pdf.isDoc, isFalse);
      expect(pdf.isUploaded, isTrue);
      expect(pdf.formattedSize, '2.0 MB');

      const docx = AttachedFile(
        id: 'file-doc-1',
        name: 'loyiha.docx',
        sizeBytes: 450 * 1024, // 450KB
        mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(docx.isDoc, isTrue);
      expect(docx.isPdf, isFalse);
      expect(docx.formattedSize, '450.0 KB');

      const img = AttachedFile(
        id: 'file-img-1',
        name: 'skrinshot.png',
        sizeBytes: 800,
        mimeType: 'image/png',
      );
      expect(img.isImage, isTrue);
      expect(img.formattedSize, '800 B');

      const uploading = AttachedFile(
        name: 'draft.csv',
        sizeBytes: 2048,
        mimeType: 'text/csv',
        isUploading: true,
      );
      expect(uploading.isCsvOrTable, isTrue);
      expect(uploading.isUploaded, isFalse);
      expect(uploading.hasError, isFalse);

      final failed = uploading.copyWith(
        isUploading: false,
        errorMessage: 'Network timeout',
      );
      expect(failed.hasError, isTrue);
      expect(failed.isUploaded, isFalse);
    });
  });

  group('ChatState Model Tests', () {
    test('ChatState default values', () {
      const state = ChatState();

      expect(state.conversationId, isNull);
      expect(state.messages, isEmpty);
      expect(state.isLoadingHistory, isFalse);
      expect(state.isGenerating, isFalse);
      expect(state.activeGenerationId, isNull);
      expect(state.errorMessage, isNull);
    });

    test('ChatState copyWith updates fields correctly', () {
      const state = ChatState();

      final updated = state.copyWith(
        conversationId: 'conv-99',
        isGenerating: true,
        activeGenerationId: 'gen-88',
        errorMessage: 'Xato',
      );

      expect(updated.conversationId, 'conv-99');
      expect(updated.isGenerating, isTrue);
      expect(updated.activeGenerationId, 'gen-88');
      expect(updated.errorMessage, 'Xato');

      final cleared = updated.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);
    });
  });
}
