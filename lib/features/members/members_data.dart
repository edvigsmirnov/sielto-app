import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// Everyone in a Space, the owner first, and this user's labels for them.
typedef MemberList = ({
  CloudResult result,
  List<Member> members,
  Map<String, MemberLabel> labels,
});

final membersProvider = FutureProvider.autoDispose.family<MemberList, String>((
  Ref ref,
  String spaceId,
) async {
  final SyncController sync = ref.read(syncProvider.notifier);
  final ({CloudResult result, List<Member> members}) loaded = await sync
      .members(spaceId);
  return (
    result: loaded.result,
    members: loaded.members,
    labels: loaded.result == CloudResult.done
        ? await sync.labels(spaceId)
        : const <String, MemberLabel>{},
  );
});

extension MemberNames on MemberList {
  /// As this user labelled [member], else their public name.
  String nameOf(Member member) =>
      labels[member.userId]?.name ?? member.name ?? tr('members.noName');

  /// Null until the cloud answers.
  int? get count => result == CloudResult.done ? members.length : null;
}
