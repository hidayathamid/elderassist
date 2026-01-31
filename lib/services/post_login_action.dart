import 'package:flutter/foundation.dart';

enum PostLoginActionType { openEmailEdit }

class PostLoginAction {
  PostLoginAction({required this.type, this.prefilledEmail});

  final PostLoginActionType type;
  final String? prefilledEmail;

  static final ValueNotifier<PostLoginAction?> _action =
      ValueNotifier<PostLoginAction?>(null);

  static void set(PostLoginAction next) {
    _action.value = next;
  }

  static PostLoginAction? take() {
    final current = _action.value;
    _action.value = null;
    return current;
  }
}
