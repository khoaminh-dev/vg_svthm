/// Điều khiển bằng giọng nói: mô hình dữ liệu dùng chung giữa API, controller và giao diện.
enum VoiceStatus { idle, listening, thinking, speaking }

enum VoiceExpect {
  command,
  freeText,
  yesNo,
  choice,
  person,
  none;

  static VoiceExpect parse(String? s) => switch (s) {
    'free_text' => freeText,
    'yes_no' => yesNo,
    'choice' => choice,
    'name' => person,
    'none' => none,
    _ => command,
  };

  String get wire => switch (this) {
    command => 'command',
    freeText => 'free_text',
    yesNo => 'yes_no',
    choice => 'choice',
    person => 'name',
    none => 'none',
  };
}

class VoiceTask {
  const VoiceTask({required this.intent, this.slots = const {}});

  factory VoiceTask.fromJson(Map<String, dynamic> j) => VoiceTask(
    intent: j['intent'] as String? ?? '',
    slots: {
      for (final e in (j['slots'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: '${e.value}',
    },
  );

  final String intent;
  final Map<String, String> slots;

  Map<String, dynamic> toJson() => {'intent': intent, 'slots': slots};
}

class VoiceChoice {
  const VoiceChoice(this.id, this.name);
  final String id;
  final String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class VoiceContact {
  const VoiceContact({
    required this.id,
    required this.kind,
    required this.name,
    this.username,
    this.aliases = const [],
  });

  final String id;
  final String kind; // direct | group
  final String name;
  final String? username;
  final List<String> aliases;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    if (username != null) 'username': username,
    'aliases': aliases,
  };
}

/// Quyết định của máy chủ cho một lượt nói.
class VoiceDecision {
  const VoiceDecision({
    required this.action,
    this.intent,
    this.task,
    this.pending,
    this.expects = VoiceExpect.none,
    this.choices = const [],
    this.say = '',
    this.sayClass = 'other',
    this.expectsReply = false,
    this.chips = const [],
    this.aliasPhrase,
  });

  factory VoiceDecision.fromJson(Map<String, dynamic> j) => VoiceDecision(
    action: j['action'] as String? ?? 'answer',
    intent: j['intent'] as String?,
    task: j['task'] == null ? null : VoiceTask.fromJson(j['task'] as Map<String, dynamic>),
    pending: j['pending'] as String?,
    expects: VoiceExpect.parse(j['expects'] as String?),
    choices: [
      for (final c in (j['choices'] as List<dynamic>? ?? const []))
        VoiceChoice((c as Map)['id'] as String, c['name'] as String),
    ],
    say: j['say'] as String? ?? '',
    sayClass: j['say_class'] as String? ?? 'other',
    expectsReply: j['expects_reply'] as bool? ?? false,
    chips: [for (final c in (j['chips'] as List<dynamic>? ?? const [])) '$c'],
    aliasPhrase: j['alias_phrase'] as String?,
  );

  final String action; // ask | confirm | execute | answer | cancel | unsupported | repeat
  final String? intent;
  final VoiceTask? task;
  final String? pending;
  final VoiceExpect expects;
  final List<VoiceChoice> choices;
  final String say;
  final String sayClass;
  final bool expectsReply;
  final List<String> chips;
  final String? aliasPhrase;
}

class VoiceTurnResult {
  const VoiceTurnResult({required this.transcript, required this.decision, this.sttProvider});

  factory VoiceTurnResult.fromJson(Map<String, dynamic> j) => VoiceTurnResult(
    transcript: j['transcript'] as String? ?? '',
    decision: VoiceDecision.fromJson(j['decision'] as Map<String, dynamic>),
    sttProvider: (j['stt'] as Map<String, dynamic>?)?['provider'] as String?,
  );

  final String transcript;
  final VoiceDecision decision;
  final String? sttProvider;
}

/// Trạng thái hội thoại gửi lên máy chủ ở lượt kế tiếp.
class VoiceDialog {
  const VoiceDialog({
    this.task,
    this.pending,
    this.expects = VoiceExpect.command,
    this.choices = const [],
    this.aliasPhrase,
  });

  final VoiceTask? task;
  final String? pending;
  final VoiceExpect expects;
  final List<VoiceChoice> choices;
  final String? aliasPhrase;

  Map<String, dynamic> toJson() => {
    if (task != null) 'task': task!.toJson(),
    if (pending != null) 'pending': pending,
    'expects': expects.wire,
    'choices': [for (final c in choices) c.toJson()],
    if (aliasPhrase != null) 'alias_phrase': aliasPhrase,
  };
}
