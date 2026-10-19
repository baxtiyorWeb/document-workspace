import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/conversation.dart';

final selectedConversationIdProvider = StateProvider<String?>((ref) => null);

final conversationsProvider =
    StateNotifierProvider<
      ConversationsNotifier,
      AsyncValue<List<Conversation>>
    >((ref) {
      final apiClient = ref.watch(apiClientProvider);
      final authState = ref.watch(authProvider);
      return ConversationsNotifier(apiClient, authState.isAuthenticated);
    });

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<Conversation>>> {
  final dynamic _apiClient;
  final bool _isAuthenticated;

  ConversationsNotifier(this._apiClient, this._isAuthenticated)
    : super(const AsyncValue.loading()) {
    if (_isAuthenticated) {
      loadConversations();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> loadConversations() async {
    state = const AsyncValue.loading();
    try {
      final data = await _apiClient.get('/api/v1/conversations');
      final list = (data as List)
          .map((json) => Conversation.fromJson(json))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Conversation?> createConversation({
    String? title,
    String? category,
  }) async {
    try {
      final data = await _apiClient.post(
        '/api/v1/conversations',
        body: {'title': title, 'category': category ?? 'general'},
      );
      final newConv = Conversation.fromJson(data);

      final current = state.value ?? [];
      state = AsyncValue.data([newConv, ...current]);
      return newConv;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateTitle(String convID, String newTitle) async {
    try {
      final data = await _apiClient.patch(
        '/api/v1/conversations/$convID',
        body: {'title': newTitle},
      );
      final updated = Conversation.fromJson(data);

      final current = state.value ?? [];
      state = AsyncValue.data(
        current.map((c) => c.id == convID ? updated : c).toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteConversation(String convID) async {
    try {
      await _apiClient.delete('/api/v1/conversations/$convID');
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((c) => c.id != convID).toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  void updateConversationLastMessage(
    String convID,
    DateTime time, {
    String? newTitle,
  }) {
    final current = state.value;
    if (current == null) return;

    final updated = current.map((c) {
      if (c.id == convID) {
        return c.copyWith(
          lastMessageAt: time,
          title: (newTitle != null && newTitle.isNotEmpty) ? newTitle : c.title,
        );
      }
      return c;
    }).toList();

    // Re-sort by latest message
    updated.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    state = AsyncValue.data(updated);
  }
}
