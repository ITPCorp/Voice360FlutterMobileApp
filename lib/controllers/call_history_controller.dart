import 'package:itp_voice/helpers/page_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/models/call_history_model.dart';
import 'package:itp_voice/repo/call_history_repo.dart';
import 'package:itp_voice/widgets/custom_toast.dart';

int itemCount = 0;
int apiLimit = 20;

class CallHistoryController extends GetxController {
  bool isLoading = false;
  bool loadFailed = false;
  CallHistoryRepo repo = CallHistoryRepo();
  List<CallHistory> callHistoryList = [];
  List<CallHistory> todayCallHistory = [];
  List<CallHistory> yesterdayCallHistory = [];
  TextEditingController searchController = TextEditingController();
  int apiOffset = 0;
  bool _hydratedFromCache = false;
  bool get hasCachedData => _hydratedFromCache;

  late ScrollController scrollController;

  void _hydrateFromCache() {
    if (!AppCache.instance.isReady || _hydratedFromCache) return;
    final cached = AppCache.instance.callHistory.readAll();
    if (cached.isEmpty) return;
    _bucketise(cached, replaceAll: true);
    _hydratedFromCache = true;
    update();
  }

  /// Bucket the call list into Today / Yesterday / Earlier.
  void _bucketise(List<CallHistory> calls, {required bool replaceAll}) {
    if (replaceAll) {
      todayCallHistory.clear();
      yesterdayCallHistory.clear();
      callHistoryList.clear();
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    for (final c in calls) {
      final t = c.time;
      if (t == null) {
        callHistoryList.add(c);
        continue;
      }
      final day = DateTime(t.year, t.month, t.day);
      if (day == today) {
        todayCallHistory.add(c);
      } else if (day == yesterday) {
        yesterdayCallHistory.add(c);
      } else {
        callHistoryList.add(c);
      }
    }
  }

  Future<void>? _pending;
  bool get refreshing => _pending != null;

  Future<void> refreshCalls() async {
    final pending = _pending;
    if (pending != null) {
      if (apiOffset == 0) return pending;
      await pending;
    }
    apiOffset = 0;
    await getCallHistory();
  }

  Future<void> getCallHistory() async {
    final pending = _pending;
    if (pending != null) return pending;
    final request = _fetch();
    _pending = request;
    try {
      await request;
    } finally {
      if (identical(_pending, request)) _pending = null;
      update();
    }
  }

  Future<void> _fetch() async {
    try {
      // Show shimmer only when the screen has nothing to render.
      final hasAny = todayCallHistory.isNotEmpty ||
          yesterdayCallHistory.isNotEmpty ||
          callHistoryList.isNotEmpty;
      isLoading = !hasAny;
      update();

      final res = await repo.fetchCallHistory(offSet: apiOffset);
      loadFailed = res is! List<CallHistory>;
      isLoading = false;

      if (res is String) {
        CustomToast.showToast('Could not load recent calls. Try again.', true);
        update();
        return;
      }
      if (res is List<CallHistory>) {
        apiOffset = apiOffset + apiLimit;
        if (apiOffset <= apiLimit) {
          // First page: swap fresh data in.
          final previous = [
            ...todayCallHistory,
            ...yesterdayCallHistory,
            ...callHistoryList
          ];
          final merged = mergeFirstPage(res, previous, (c) => c.cdrPk,
              hasMore: res.length >= apiLimit);
          apiOffset = merged.length;
          _bucketise(merged, replaceAll: true);
          if (AppCache.instance.isReady) {
            AppCache.instance.callHistory.writeAll(merged);
          }
        } else {
          // Append for pagination.
          _bucketise(res, replaceAll: false);
          if (AppCache.instance.isReady) {
            final combined = [
              ...todayCallHistory,
              ...yesterdayCallHistory,
              ...callHistoryList,
            ];
            AppCache.instance.callHistory.writeAll(combined);
          }
        }
      }
    } finally {
      isLoading = false;
      update();
    }
  }

  dynamic getDataList(String type, bool missedOnly) {
    final src = switch (type) {
      'today' => todayCallHistory,
      'yesterday' => yesterdayCallHistory,
      _ => callHistoryList,
    };
    Iterable<CallHistory> filtered = src;
    if (missedOnly) {
      filtered = filtered
          .where((c) => (c.isMissed ?? false) && (c.isIncoming ?? false));
    }
    final q = searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered =
          filtered.where((c) => (c.name ?? '').toLowerCase().contains(q));
    }
    return filtered.toList();
  }

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController();
    scrollController.addListener(() {
      if (scrollController.position.pixels ==
              scrollController.position.maxScrollExtent &&
          apiOffset < itemCount) {
        getCallHistory();
      }
    });
    _hydrateFromCache();
    getCallHistory();
  }
}
